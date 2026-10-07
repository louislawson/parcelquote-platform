# Re-exported from the module rather than dropped. The deploy stage reads app_fqdn with
# terraform output -raw, so removing these would apply cleanly and then fail the smoke test
# afterwards, which is the worst order to find out.
output "app_fqdn" {
  description = "Stable hostname, serving whichever revisions the traffic weights point at."
  value       = module.workload.app_fqdn
}

output "latest_revision_fqdn" {
  description = "Hostname of the newest revision, reachable regardless of traffic weighting. The smoke test uses this so it asserts against the revision the run produced."
  value       = module.workload.latest_revision_fqdn
}

output "latest_revision_name" {
  description = "Name of the newest revision, for correlating container logs and shifting traffic."
  value       = module.workload.latest_revision_name
}
