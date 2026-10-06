# State moves for the extraction of infra/modules/workload, which was a pure refactor: every
# resource below kept its configuration and only changed address. Five also dropped the _dev
# suffix from their label, because a shared module cannot call its container app ca_dev and
# stay honest when prod calls it. Renaming here rather than later is deliberate: a moved block
# carries the rename and the move together, so doing it in the same change costs nothing,
# while doing it afterwards would mean a second state move against live resources.
#
# Without these blocks
# Terraform reads the new addresses as new resources and plans a destroy and a create for each,
# which for the workspace would discard its data and every alert scoped to it. Nothing warns
# first, so the gate is a plan reporting no changes.
#
# The three data sources need no entries. A moved block accepts managed resources and module
# calls only, and pointing one at a data source is an error; they are re-read every plan and
# move silently.
#
# These are safe to delete once every environment reading this state has applied once. Keeping
# them through phase 6 costs nothing and keeps the refactor legible in the diff.

moved {
  from = azurerm_log_analytics_workspace.log_dev
  to   = module.workload.azurerm_log_analytics_workspace.log
}

moved {
  from = azurerm_container_app_environment.cae_env
  to   = module.workload.azurerm_container_app_environment.cae_env
}

moved {
  from = azurerm_monitor_diagnostic_setting.diag_cae_env
  to   = module.workload.azurerm_monitor_diagnostic_setting.diag_cae_env
}

moved {
  from = azurerm_application_insights.appi_dev
  to   = module.workload.azurerm_application_insights.appi
}

moved {
  from = azurerm_container_app.ca_dev
  to   = module.workload.azurerm_container_app.ca
}

moved {
  from = azurerm_monitor_action_group.ag_dev
  to   = module.workload.azurerm_monitor_action_group.ag
}

moved {
  from = azurerm_monitor_scheduled_query_rules_alert_v2.alert_5xx
  to   = module.workload.azurerm_monitor_scheduled_query_rules_alert_v2.alert_5xx
}

moved {
  from = azurerm_monitor_scheduled_query_rules_alert_v2.alert_latency
  to   = module.workload.azurerm_monitor_scheduled_query_rules_alert_v2.alert_latency
}

moved {
  from = azurerm_application_insights_standard_web_test.wt_dev
  to   = module.workload.azurerm_application_insights_standard_web_test.wt
}

moved {
  from = azurerm_monitor_metric_alert.alert_availability
  to   = module.workload.azurerm_monitor_metric_alert.alert_availability
}
