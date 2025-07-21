static_resources:
  listeners:
  - name: listener_0
    address:
      socket_address:
        address: 0.0.0.0
        port_value: 8000
    filter_chains:
    - filters:
      - name: envoy.filters.network.http_connection_manager
        typed_config:
          "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
          stat_prefix: ingress_http
          access_log:
          - name: envoy.access_loggers.stdout
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.access_loggers.stream.v3.StdoutAccessLog
          route_config:
            name: local_route
            virtual_hosts:
            - name: backend
              domains: ["*"]
              routes:
              # Health check route
              - match:
                  path: "/health"
                direct_response:
                  status: 200
                  body:
                    inline_string: "OK"
              # Dynamic shard routes based on x-tenant-shard header
%{ for shard_name in shard_names ~}
              - match:
                  prefix: "/"
                  headers:
                  - name: x-tenant-shard
                    exact_match: "${shard_name}"
                route:
                  cluster: ${shard_name}
%{ endfor ~}
              # Default route when no shard header matches
              - match:
                  prefix: "/"
                route:
                  cluster: ${default_shard}
          http_filters:
          # Lua filter for tenant lookup
          - name: envoy.filters.http.lua
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.http.lua.v3.Lua
              default_source_code:
                inline_string: |
                  function envoy_on_request(request_handle)
                    -- Get the host header
                    local host = request_handle:headers():get(":authority")
                    if not host then
                      host = request_handle:headers():get("host")
                    end
                    
                    if host then
                      -- Call the tenant lookup service
                      local headers, body = request_handle:httpCall(
                        "tenant_lookup_cluster",
                        {
                          [":method"] = "GET",
                          [":path"] = "/lookup?host=" .. host,
                          [":authority"] = "tenant-lookup"
                        },
                        "",
                        5000
                      )
                      
                      if headers and headers[":status"] == "200" and body then
                        -- Parse JSON response manually (Envoy Lua doesn't have cjson)
                        -- Expected format: {"shard":"shard1","tenant":"tenant1"}
                        local shard = string.match(body, '"shard":"([^"]+)"')
                        local tenant = string.match(body, '"tenant":"([^"]+)"')
                        
                        if shard then
                          -- Set the shard header
                          request_handle:headers():add("x-tenant-shard", shard)
                          
                          if tenant then
                            request_handle:headers():add("x-tenant-name", tenant)
                          end
                          
                          request_handle:logInfo("Tenant lookup: " .. host .. " -> " .. shard)
                        else
                          request_handle:logWarn("Failed to parse tenant lookup response: " .. body)
                        end
                      else
                        request_handle:logWarn("Tenant lookup failed for host: " .. host)
                      end
                    end
                  end
          - name: envoy.filters.http.router
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.http.router.v3.Router

  clusters:
  # Tenant lookup service cluster
  - name: tenant_lookup_cluster
    connect_timeout: 0.25s
    type: STATIC
    lb_policy: ROUND_ROBIN
    load_assignment:
      cluster_name: tenant_lookup_cluster
      endpoints:
      - lb_endpoints:
        - endpoint:
            address:
              socket_address:
                address: 127.0.0.1
                port_value: 8080
                
  # Dynamic cluster configuration for each shard ALB
%{ for shard_name in shard_names ~}
  - name: ${shard_name}
    connect_timeout: 5s
    type: LOGICAL_DNS
    dns_lookup_family: V4_ONLY
    lb_policy: ROUND_ROBIN
    load_assignment:
      cluster_name: ${shard_name}
      endpoints:
      - lb_endpoints:
        - endpoint:
            address:
              socket_address:
                # Points to the shard's Application Load Balancer
                address: ${shard_backends[shard_name].shard_alb_ip}
                port_value: 80
%{ endfor ~}

admin:
  address:
    socket_address:
      address: 0.0.0.0
      port_value: 9901