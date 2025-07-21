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
          - name: envoy.filters.http.wasm
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.http.wasm.v3.Wasm
              config:
                root_id: "tenant_router"
                vm_config:
                  vm_id: "tenant_router"
                  runtime: "envoy.wasm.runtime.v8"
                  code:
                    local:
                      filename: "/opt/envoy/tenant-router.wasm"
                configuration:
                  "@type": "type.googleapis.com/google.protobuf.StringValue"
                  value: |
                    {
                      "gcs_bucket": "${gcs_bucket_name}",
                      "cache_ttl_seconds": 300,
                      "default_shard": "${default_shard}"
                    }
          - name: envoy.filters.http.router
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.http.router.v3.Router

  clusters:
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

  # Local GCS proxy cluster for WASM filter to fetch tenant mappings
  - name: gcs_proxy
    connect_timeout: 5s
    type: STATIC
    lb_policy: ROUND_ROBIN
    load_assignment:
      cluster_name: gcs_proxy
      endpoints:
      - lb_endpoints:
        - endpoint:
            address:
              socket_address:
                address: 127.0.0.1
                port_value: 8080

admin:
  address:
    socket_address:
      address: 0.0.0.0
      port_value: 9901