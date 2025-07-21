# Monitoring and alerting for Envoy deployment (single-region or global)

# Create a monitoring dashboard for Envoy metrics
resource "google_monitoring_dashboard" "envoy" {
  count = var.use_global_deployment ? 1 : 0
  dashboard_json = jsonencode({
    displayName = "${var.name_prefix} Global Envoy Dashboard"
    mosaicLayout = {
      columns = 12
      tiles = [
        {
          width  = 6
          height = 4
          xPos   = 0
          yPos   = 0
          widget = {
            title = "Requests per Second by Region"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"loadbalancing.googleapis.com/https/request_count\" resource.type=\"https_lb_rule\""
                    aggregation = {
                      alignmentPeriod    = "60s"
                      perSeriesAligner   = "ALIGN_RATE"
                      crossSeriesReducer = "REDUCE_SUM"
                      groupByFields      = ["resource.label.region"]
                    }
                  }
                }
              }]
            }
          }
        },
        {
          width  = 6
          height = 4
          xPos   = 6
          yPos   = 0
          widget = {
            title = "Backend Latency by Region (p95)"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"loadbalancing.googleapis.com/https/backend_latencies\" resource.type=\"https_lb_rule\""
                    aggregation = {
                      alignmentPeriod    = "60s"
                      perSeriesAligner   = "ALIGN_PERCENTILE_95"
                      crossSeriesReducer = "REDUCE_MEAN"
                      groupByFields      = ["resource.label.region"]
                    }
                  }
                }
              }]
            }
          }
        },
        {
          width  = 4
          height = 4
          xPos   = 0
          yPos   = 4
          widget = {
            title = "Healthy Instances by Region"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"compute.googleapis.com/instance_group/size\" resource.type=\"instance_group\""
                    aggregation = {
                      alignmentPeriod    = "60s"
                      perSeriesAligner   = "ALIGN_MEAN"
                      crossSeriesReducer = "REDUCE_SUM"
                      groupByFields      = ["resource.label.location"]
                    }
                  }
                }
              }]
            }
          }
        },
        {
          width  = 4
          height = 4
          xPos   = 4
          yPos   = 4
          widget = {
            title = "Error Rate by Region"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"loadbalancing.googleapis.com/https/request_count\" resource.type=\"https_lb_rule\" metric.label.response_code_class=\"500\""
                    aggregation = {
                      alignmentPeriod    = "60s"
                      perSeriesAligner   = "ALIGN_RATE"
                      crossSeriesReducer = "REDUCE_SUM"
                      groupByFields      = ["resource.label.region"]
                    }
                  }
                }
              }]
            }
          }
        },
        {
          width  = 4
          height = 4
          xPos   = 8
          yPos   = 4
          widget = {
            title = "CPU Utilization by Region"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"compute.googleapis.com/instance/cpu/utilization\" metadata.user_labels.\"envoy-region\"!=\"\""
                    aggregation = {
                      alignmentPeriod    = "60s"
                      perSeriesAligner   = "ALIGN_MEAN"
                      crossSeriesReducer = "REDUCE_MEAN"
                      groupByFields      = ["metadata.user_labels.envoy-region"]
                    }
                  }
                }
              }]
            }
          }
        }
      ]
    }
  })
}

# Alert policies for global monitoring
resource "google_monitoring_alert_policy" "envoy_high_error_rate" {
  display_name = "${var.name_prefix} Envoy High Error Rate"
  combiner     = "OR"

  conditions {
    display_name = "5xx error rate > 5%"
    
    condition_threshold {
      filter          = "metric.type=\"loadbalancing.googleapis.com/https/request_count\" resource.type=\"https_lb_rule\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0.05

      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields      = ["resource.label.region"]
      }

      trigger {
        count = 1
      }
    }
  }

  notification_channels = var.notification_channel_ids

  alert_strategy {
    auto_close = "1800s"
  }
}

resource "google_monitoring_alert_policy" "envoy_high_latency" {
  display_name = "${var.name_prefix} Envoy High Latency"
  combiner     = "OR"

  conditions {
    display_name = "Backend latency p95 > 1s"
    
    condition_threshold {
      filter          = "metric.type=\"loadbalancing.googleapis.com/https/backend_latencies\" resource.type=\"https_lb_rule\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 1000 # milliseconds

      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_PERCENTILE_95"
        cross_series_reducer = "REDUCE_MEAN"
        group_by_fields      = ["resource.label.region"]
      }

      trigger {
        count = 1
      }
    }
  }

  notification_channels = var.notification_channel_ids
}

resource "google_monitoring_alert_policy" "envoy_instance_health" {
  display_name = "${var.name_prefix} Envoy Instance Health"
  combiner     = "OR"

  conditions {
    display_name = "Unhealthy instances in region"
    
    condition_threshold {
      filter          = "metric.type=\"compute.googleapis.com/instance_group/size\" resource.type=\"instance_group\""
      duration        = "300s"
      comparison      = "COMPARISON_LT"
      threshold_value = 2 # Less than 2 healthy instances

      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_MEAN"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields      = ["resource.label.location"]
      }

      trigger {
        count = 1
      }
    }
  }

  notification_channels = var.notification_channel_ids
}

# Global uptime check for Envoy health
resource "google_monitoring_uptime_check_config" "envoy_global" {
  count = var.use_global_deployment ? 1 : 0

  display_name = "${var.name_prefix} Envoy Global Health"
  timeout      = "10s"
  period       = "60s"

  http_check {
    path         = "/health"
    port         = "80"
    use_ssl      = false
    validate_ssl = false
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = var.project_id
      host       = module.main_load_balancer_global[0].load_balancer_ip
    }
  }

  # Use multiple regions for global monitoring
  selected_regions = ["USA", "EUROPE", "ASIA_PACIFIC"]
}

# SLO for global Envoy availability
resource "google_monitoring_slo" "envoy_availability" {
  service      = google_monitoring_service.envoy.service_id
  slo_id       = "envoy-availability-slo"
  display_name = "Envoy Global Availability"

  goal                = 0.999 # 99.9% availability
  rolling_period_days = 30

  request_based_sli {
    good_total_ratio {
      good_service_filter = "metric.type=\"loadbalancing.googleapis.com/https/request_count\" resource.type=\"https_lb_rule\" metric.label.response_code_class!=500"
      total_service_filter = "metric.type=\"loadbalancing.googleapis.com/https/request_count\" resource.type=\"https_lb_rule\""
    }
  }
}

resource "google_monitoring_service" "envoy" {
  service_id   = "${var.name_prefix}-envoy-service"
  display_name = "${var.name_prefix} Envoy Service"

  basic_service {
    service_type = "CLOUD_RUN"
    service_labels = {
      service_name = "${var.name_prefix}-envoy"
      location     = "global"
    }
  }
}

# Custom metrics for tenant routing performance
resource "google_logging_metric" "tenant_lookup_latency" {
  name   = "${var.name_prefix}_tenant_lookup_latency"
  filter = "resource.type=\"gce_instance\" AND jsonPayload.component=\"envoy\" AND jsonPayload.metric=\"tenant_lookup_latency_ms\""

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "DISTRIBUTION"
    unit        = "ms"
    
    labels {
      key         = "region"
      value_type  = "STRING"
      description = "Region where the lookup occurred"
    }
  }

  value_extractor = "EXTRACT(jsonPayload.latency_ms)"
  
  label_extractors = {
    "region" = "EXTRACT(resource.labels.zone)"
  }

  bucket_options {
    exponential_buckets {
      num_finite_buckets = 64
      growth_factor      = 2
      scale              = 0.01
    }
  }
}

# Export to BigQuery for long-term analysis
resource "google_logging_project_sink" "envoy_metrics_export" {
  name        = "${var.name_prefix}-envoy-metrics-export"
  destination = "bigquery.googleapis.com/projects/${var.project_id}/datasets/${var.bigquery_dataset_id}"

  filter = "resource.type=\"https_lb_rule\" OR (resource.type=\"gce_instance\" AND resource.labels.instance_name=~\"^${var.name_prefix}-envoy-.*\")"

  bigquery_options {
    use_partitioned_tables = true
  }
}