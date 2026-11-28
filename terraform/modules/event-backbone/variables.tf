variable "kafka_version" {
  description = "Apache Kafka protocol version"
  type        = string
  default     = "3.8.0"
}

variable "valkey_version" {
  description = "Valkey / Redis RESP3 engine version"
  type        = string
  default     = "8.0"
}
