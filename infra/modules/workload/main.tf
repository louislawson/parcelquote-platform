# In main.tf rather than the locals.tf HashiCorp's file layout suggests, matching the environment
# roots, which keep their locals at the top of main.tf too. The split would be defensible in a
# file this long; having one convention across the repository won.
locals {
  # A revision has to be nameable before it exists: a traffic weight names one, and the pipeline
  # builds a hostname for another. Left unset the service generates a hash, which could only be
  # read back afterwards — and reading it back is exactly what the provider gets wrong, since
  # latest_revision_name is one revision stale immediately after an apply. The v is not
  # decoration: Azure requires a suffix to start with an alphabetic character and roughly three
  # short SHAs in eight start with a digit.
  revision_suffix = "v${var.image_tag}"

  # Built as one list rather than written as blocks because traffic_weight is an ordered list in
  # the provider schema, not a set. Two configurations producing the same weights in a different
  # order would plan a change, so the order has to come from somewhere deliberate.
  #
  # Two shapes, and which one applies turns on whether a stable revision has been named rather
  # than on the revision mode. Naming both revisions is what allows a weight to be moved between
  # them, so that is the blue/green shape. The other shape puts the whole weight on
  # latest_revision, and that is not just the only thing Single mode can express — it is the
  # safer answer whenever a revision takes all the traffic without having been verified first.
  # Azure holds traffic on the outgoing revision until the new one passes its probes, but the
  # documentation promises that only for latest_revision; a named revision at 100% is not
  # described as waiting for anything. Once a stable revision exists the candidate arrives at 0%
  # and is verified before it is promoted, so there is nothing left for that gate to protect.
  traffic_weights = var.revision_mode == "Multiple" && var.stable_revision_suffix != "" ? [
    {
      revision_suffix = local.revision_suffix
      label           = "green"
      latest_revision = false
      percentage      = var.candidate_percentage
    },
    {
      revision_suffix = var.stable_revision_suffix
      label           = "blue"
      latest_revision = false
      percentage      = 100 - var.candidate_percentage
    },
    ] : [
    {
      revision_suffix = null
      label           = var.revision_mode == "Multiple" ? "green" : null
      latest_revision = true
      percentage      = 100
    }
  ]
}

data "azurerm_resource_group" "rg" {
  name = "rg-${var.project_app_service}-${var.environment}-${var.location_short}-01"
}

data "azurerm_user_assigned_identity" "container_app" {
  resource_group_name = data.azurerm_resource_group.rg.name
  name                = "id-${var.project_app_service}-${var.environment}-${var.location_short}-01"
}

data "azurerm_key_vault" "kv" {
  name                = "kv-${var.project_app_service}-${var.environment}-${var.location_short}"
  resource_group_name = data.azurerm_resource_group.rg.name
}

resource "azurerm_log_analytics_workspace" "log" {
  name                = "log-${var.project_app_service}-${var.environment}-${var.location_short}-01"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags

  # Off because the environment ships logs through a diagnostic setting rather than the
  # shared-key ingestion that logs_destination = "log-analytics" requires. The two are
  # coupled: reverting that destination forces this back to true and puts a live workspace
  # key back into Terraform state. See Gotchas in README.md.
  local_authentication_enabled = false
}

resource "azurerm_container_app_environment" "cae_env" {
  name                = "cae-${var.project_app_service}-${var.environment}-${var.location_short}-01"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
  logs_destination    = "azure-monitor"
  tags                = var.tags

  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
  }
}

resource "azurerm_monitor_diagnostic_setting" "diag_cae_env" {
  name                       = "diag-${var.project_app_service}-${var.environment}-${var.location_short}-01"
  target_resource_id         = azurerm_container_app_environment.cae_env.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.log.id

  # No log_analytics_destination_type, deliberately. A managed environment only supports
  # resource-specific tables, so the argument is unconfigurable for this target and Azure never
  # echoes it back: setting it to "Dedicated" changed nothing and made every subsequent plan
  # want to set it again. The per-category tables, ContainerAppHTTPLogs among them, are what
  # this resource type produces regardless.

  # Logs only. AllMetrics is offered here, but platform metrics are already queryable
  # through Azure Monitor without paying Log Analytics ingestion for a second copy.
  enabled_log { category = "ContainerAppConsoleLogs" }
  enabled_log { category = "ContainerAppSystemLogs" }
  enabled_log { category = "ContainerAppHTTPLogs" }
}

# Three of these are decisions rather than settings, and the comment is here rather than beside
# each one because a comment inside the block splits the alignment into groups.
#
# daily_data_cap_in_gb defaults to 100, and ingestion is $2.88/GB in UK South — a $288-a-day
# ceiling on an environment whose standing cost is about £4 a month. local_authentication_enabled
# is what makes the bootstrap grant necessary and the connection string below harmless: Terraform
# mints this component, so the string is in state whatever we do, and the achievable outcome is
# that the key stops working rather than that it is absent. sampling_percentage is the provider
# default, stated because 100 reads as an oversight — at a handful of requests a day, sampling
# would leave too few traces to be worth querying.
resource "azurerm_application_insights" "appi" {
  name                         = "appi-${var.project_app_service}-${var.environment}-${var.location_short}-01"
  location                     = data.azurerm_resource_group.rg.location
  resource_group_name          = data.azurerm_resource_group.rg.name
  workspace_id                 = azurerm_log_analytics_workspace.log.id
  application_type             = "web"
  daily_data_cap_in_gb         = 1
  retention_in_days            = 30
  local_authentication_enabled = false
  sampling_percentage          = 100
  tags                         = var.tags
}

resource "azurerm_container_app" "ca" {
  name                         = "ca-${var.project_app_service}-${var.environment}-${var.location_short}-01"
  container_app_environment_id = azurerm_container_app_environment.cae_env.id
  resource_group_name          = data.azurerm_resource_group.rg.name
  revision_mode                = var.revision_mode
  workload_profile_name        = "Consumption"
  tags                         = var.tags

  # Bounds the list of revisions Azure keeps after they go inactive, and nothing else. In
  # Multiple mode no revision becomes inactive unless something deactivates it, and nothing here
  # does — so this is inert wherever revision_mode is Multiple, and it is not what limits how
  # many revisions such an environment accumulates. That limit is Azure's own ceiling of one
  # hundred, oldest purged, and nothing watches the count.
  max_inactive_revisions = 3

  identity {
    type         = "UserAssigned"
    identity_ids = [data.azurerm_user_assigned_identity.container_app.id]
  }

  registry {
    server   = var.registry_login_server
    identity = data.azurerm_user_assigned_identity.container_app.id
  }

  # A Key Vault reference, not a value. Container Apps resolves it with the managed
  # identity, so the secret never passes through Terraform and lands in neither state
  # nor a plan file; replacing this with `value = ...` would put it in both. The id is
  # versionless and vault_uri already ends in a slash, so a rotation needs no change here
  # and no deployment either: the platform fetches the newest version and restarts the
  # revisions referencing it, measured at 23 to 25 minutes against a documented half hour.
  # Pinning a version in this id would turn that off, which is the one thing here not to
  # tidy. What hid this for two phases: measured inside the refresh window, a restart
  # re-injects the old value, which makes "rotation needs a deployment" look proven.
  secret {
    name                = "quote-api-key"
    identity            = data.azurerm_user_assigned_identity.container_app.id
    key_vault_secret_id = "${data.azurerm_key_vault.kv.vault_uri}secrets/quote-api-key"
  }

  ingress {
    external_enabled           = true
    target_port                = 8000
    allow_insecure_connections = false

    # A label gives a revision its own hostname, app---label rather than app, and that hostname
    # is reachable whatever weight the revision carries. That is what makes verifying a revision
    # before it serves anyone possible at all. The labels here do not swap roles between
    # deployments the way Microsoft's blue/green guidance has them do: green is always the
    # revision arriving and blue always the one it replaced, so the hostname to test is the same
    # string every time. Alternating would mean the configuration had to know which colour is
    # currently live, which is state that would have to live somewhere outside it.
    dynamic "traffic_weight" {
      for_each = local.traffic_weights
      content {
        revision_suffix = traffic_weight.value.revision_suffix
        label           = traffic_weight.value.label
        latest_revision = traffic_weight.value.latest_revision
        percentage      = traffic_weight.value.percentage
      }
    }
  }

  template {
    min_replicas = 0

    # Changing this is what creates a revision; everything else in this block rides along. It
    # must be unique for the life of the app, which is why rolling back is a traffic shift and
    # can never be a redeployment of the previous tag — that suffix is already spent.
    #
    # The same rule has a second consequence, less obvious and worth knowing before it is met:
    # because the value comes from the commit, any change to this block that does not arrive
    # with a new commit cannot be applied at all. The realistic trigger is Application Insights
    # being recreated, which rewrites the connection string below. It fails loudly on apply
    # rather than quietly, but the error names a duplicate suffix and not the cause.
    revision_suffix = local.revision_suffix

    container {
      name   = "api"
      image  = "${var.registry_login_server}/${var.image_repository}:${var.image_tag}"
      cpu    = 0.25
      memory = "0.5Gi"

      env {
        name        = "QUOTE_API_KEY"
        secret_name = "quote-api-key"
      }

      # A plain value, unlike the API key above, and deliberately so. With
      # local_authentication_enabled = false on the component this string is an ingestion
      # endpoint and a resource id rather than a credential — the instrumentation key inside it
      # no longer authenticates anything. A secret block here would make `secret` stop meaning
      # "this is a credential", which is the only thing distinguishing the block above. Turning
      # local auth back on must move this into a secret block in the same change, because that
      # one edit is what would turn this into an exposed live credential.
      env {
        name  = "APPLICATIONINSIGHTS_CONNECTION_STRING"
        value = azurerm_application_insights.appi.connection_string
      }

      # Selects Entra authentication and names the identity to use, which is required because a
      # user-assigned identity cannot be inferred — there is no system-assigned one to fall back
      # to. The client id is not a credential. This replaces passing a credential in application
      # code: if the distro honours it, the app needs no azure-identity dependency at all.
      env {
        name  = "APPLICATIONINSIGHTS_AUTHENTICATION_STRING"
        value = "Authorization=AAD;ClientId=${data.azurerm_user_assigned_identity.container_app.client_id}"
      }

      # The two probes below fire every ten seconds each, so tracing them would add some 17,000
      # spans a day of no interest and crowd the real requests out of every Application Insights
      # view. The value is a comma-separated list of regexes joined with | and searched against
      # the whole URL, so these match without anchoring. /version is deliberately not excluded:
      # the smoke test polls it a few times per deploy, and which commit served a request is
      # worth a span.
      env {
        name  = "OTEL_PYTHON_EXCLUDED_URLS"
        value = "healthz,readyz"
      }

      liveness_probe {
        transport               = "HTTP"
        path                    = "/healthz"
        port                    = 8000
        initial_delay           = 5
        interval_seconds        = 10
        failure_count_threshold = 3
        timeout                 = 2
      }

      readiness_probe {
        transport               = "HTTP"
        path                    = "/readyz"
        port                    = 8000
        initial_delay           = 10
        interval_seconds        = 10
        failure_count_threshold = 3
        timeout                 = 2
      }
    }
  }
}

# ----------------------
# ALERTING
# ----------------------

# No location argument: action groups are global and the provider defaults accordingly. Every
# other resource in this file takes one, so its absence here is deliberate rather than an
# oversight. short_name is the awkward one — the provider does not validate it and the schema
# documents no limit, but Azure caps it around twelve characters, so a wrong value fails at
# apply rather than at validate or plan. "parcelquote-dev" is fifteen and would not survive,
# which is why this is an abbreviation rather than the name pattern every other resource uses.
# Interpolating the environment keeps it under the cap for any plausible name: an environment
# called something ten characters long would be the first to break it.
resource "azurerm_monitor_action_group" "ag" {
  name                = "ag-${var.project_app_service}-${var.environment}-${var.location_short}-01"
  resource_group_name = data.azurerm_resource_group.rg.name
  short_name          = "pq${var.environment}"
  tags                = var.tags

  # The address comes from a pipeline variable, so it is never written into this repository.
  # use_common_alert_schema because this environment raises both scheduled-query and metric
  # alerts, and without it the two arrive in different payload shapes.
  email_receiver {
    name                    = "owner"
    email_address           = var.owner
    use_common_alert_schema = true
  }
}

# Both scheduled query rules are scoped to the workspace rather than to Application Insights,
# and that choice decides the table names. Workspace-based Application Insights stores its data
# in the workspace, where the tables are AppRequests and friends; scoped to the component
# instead, the same data is queried as `requests`. Getting the pair wrong names a table that
# does not exist — caught at apply, because skip_query_validation is left at its default of
# false, which is worth keeping.
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "alert_5xx" {
  name                = "alert-5xx-${var.project_app_service}-${var.environment}-${var.location_short}-01"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = data.azurerm_resource_group.rg.location
  scopes              = [azurerm_log_analytics_workspace.log.id]
  severity            = 2
  display_name        = "parcelquote ${var.environment} - server errors"
  description         = "Any 5xx seen by the ingress in the last fifteen minutes."

  # Fifteen minutes everywhere, and not for detection speed. Container Apps logs take a few
  # minutes to arrive, so a five-minute window can be evaluated before the data it covers has
  # landed, which reads as no-data rather than as a miss, intermittently.
  evaluation_frequency    = "PT15M"
  window_duration         = "PT15M"
  auto_mitigation_enabled = true

  tags = var.tags

  criteria {
    # >= 500 excludes the noise by construction instead of by filtering. StatusCode 0 is a
    # client abandoning a cold start, not a server fault, and 401 is expected traffic.
    query                   = "ContainerAppHTTPLogs | where StatusCode >= 500"
    time_aggregation_method = "Count"
    operator                = "GreaterThan"
    threshold               = 0

    # Zero, and it cannot usefully be higher. At four availability probes an hour a
    # fifteen-minute window holds one sample, so any threshold needing two failures could never
    # fire during an outage that only the probe witnesses. The cost is that a transient 5xx
    # during a revision switch will fire; that is worth observing before suppressing.
    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.ag.id]
    email_subject = "parcelquote ${var.environment}: server errors"
  }
}

# Deliberately AppRequests and not ContainerAppHTTPLogs. The span starts when the request
# reaches the application, so the forty-odd seconds a caller waits for a cold container is not
# in it: measured over the same traffic, this table's maximum was 2 ms against the ingress
# logs' 48,224 ms. The ingress view is the honest user-facing number, but on an app that scales
# to zero with no real users it measures a design choice rather than a regression, and the
# availability test below covers that path as a binary instead.
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "alert_latency" {
  name                = "alert-latency-${var.project_app_service}-${var.environment}-${var.location_short}-01"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = data.azurerm_resource_group.rg.location
  scopes              = [azurerm_log_analytics_workspace.log.id]
  severity            = 3
  display_name        = "parcelquote ${var.environment} - request latency"
  description         = "Application-side p95 above 250 ms over fifteen minutes."

  evaluation_frequency    = "PT15M"
  window_duration         = "PT15M"
  auto_mitigation_enabled = true

  tags = var.tags

  criteria {
    query                   = <<-QUERY
      AppRequests
      | where Success == true
      | summarize p95 = percentile(DurationMs, 95)
    QUERY
    time_aggregation_method = "Average"
    metric_measure_column   = "p95"
    operator                = "GreaterThan"

    # 250 ms against an observed p95 of 2 ms. Two orders of magnitude of headroom is deliberate:
    # the handler does arithmetic and no I/O, so anything approaching this means a blocking call
    # or a dependency has appeared. A tighter threshold on a 2 ms baseline alerts on jitter.
    threshold = 250

    # Locked to one period, not chosen. The query summarises without a bin, so it projects no
    # timestamp column, and the API requires number_of_evaluation_periods = 1 in that case.
    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.ag.id]
    email_subject = "parcelquote ${var.environment}: request latency"
  }
}

# One location every fifteen minutes, which is a cost decision rather than a detection one. The
# consumption free grant covers roughly 200 hours a month of this container, and every probe
# keeps it alive for the five-minute scale-down cooldown, so a five-minute interval would hold
# the app awake permanently. A second location can cost four times one rather than twice,
# depending on how Azure staggers them. Nothing here has an SLA, so fifteen minutes costs
# nothing worth having.
resource "azurerm_application_insights_standard_web_test" "wt" {
  name                    = "wt-${var.project_app_service}-${var.environment}-${var.location_short}-01"
  resource_group_name     = data.azurerm_resource_group.rg.name
  location                = data.azurerm_resource_group.rg.location
  application_insights_id = azurerm_application_insights.appi.id
  description             = "Polls /healthz from UK South."

  # emea-ru-msa-edge is UK South. The tags are legacy and do not match the regions they label,
  # so this was read from the API rather than guessed:
  # GET <component id>/syntheticmonitorlocations?api-version=2015-05-01
  geo_locations = ["emea-ru-msa-edge"]

  # 300, 600 and 900 are the only valid frequencies. The timeout is the trap: it defaults to 30
  # seconds and a measured cold start here is 48, so the default fails every test the app is
  # asleep for, which is monitoring reporting an outage it caused itself. retry_enabled is belt
  # and braces, since the first attempt wakes the container and a retry lands warm.
  frequency     = 900
  timeout       = 120
  retry_enabled = true
  enabled       = true

  tags = var.tags

  request {
    # /healthz is unauthenticated deliberately, and implicitly covers readiness: the ingress
    # will not route to an unready replica, so a readiness failure fails this test too.
    url = "https://${one(azurerm_container_app.ca.ingress).fqdn}/healthz"
  }

  validation_rules {
    # Checks the chain, which would be our fault if ingress were misconfigured. No
    # ssl_cert_remaining_lifetime: the certificate on azurecontainerapps.io is Microsoft's, so
    # alerting on its remaining days would be alerting on somebody else's renewal. That becomes
    # worth setting when a custom domain arrives.
    ssl_check_enabled = true
  }
}

# A metric alert rather than a scheduled query, and it needs both resource ids in scopes as
# well as repeated inside the criteria block. One is not enough and the error does not say so.
resource "azurerm_monitor_metric_alert" "alert_availability" {
  name                = "alert-availability-${var.project_app_service}-${var.environment}-${var.location_short}-01"
  resource_group_name = data.azurerm_resource_group.rg.name
  severity            = 1
  description         = "The availability test failed from its only location."
  frequency           = "PT15M"
  window_size         = "PT15M"
  auto_mitigate       = true

  scopes = [
    azurerm_application_insights_standard_web_test.wt.id,
    azurerm_application_insights.appi.id,
  ]

  tags = var.tags

  # One sample per window, because the test runs every fifteen minutes. That is adequate only
  # because retry_enabled is set on the test: a reported failure already represents two failed
  # attempts, so the suppression lives there rather than here.
  application_insights_web_test_location_availability_criteria {
    web_test_id           = azurerm_application_insights_standard_web_test.wt.id
    component_id          = azurerm_application_insights.appi.id
    failed_location_count = 1
  }

  action {
    action_group_id = azurerm_monitor_action_group.ag.id
  }
}
