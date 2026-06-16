output "job_id" {
  description = "Dataflow job ID (empty until template spec is published)"
  value       = local.create_job == 1 ? google_dataflow_flex_template_job.scrubber[0].job_id : ""
}

output "job_state" {
  value = local.create_job == 1 ? google_dataflow_flex_template_job.scrubber[0].state : "not-created"
}
