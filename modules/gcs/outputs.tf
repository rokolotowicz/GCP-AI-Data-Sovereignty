output "raw_bucket_name" {
  value = google_storage_bucket.raw.name
}

output "cleaned_bucket_name" {
  value = google_storage_bucket.cleaned.name
}

output "vectors_bucket_name" {
  value = google_storage_bucket.vectors.name
}

output "dataflow_bucket_name" {
  value = google_storage_bucket.dataflow.name
}

output "raw_bucket_url" {
  value = google_storage_bucket.raw.url
}

output "cleaned_bucket_url" {
  value = google_storage_bucket.cleaned.url
}
