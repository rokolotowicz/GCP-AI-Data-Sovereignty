output "topic_id" {
  value = google_pubsub_topic.ingest.id
}

output "topic_name" {
  value = google_pubsub_topic.ingest.name
}

output "subscription_id" {
  value = google_pubsub_subscription.dataflow.id
}

output "subscription_name" {
  value = google_pubsub_subscription.dataflow.name
}
