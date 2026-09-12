variable "name" {
  description = "name for this module."
  type        = string
}

variable "buckets" {
  description = "buckets for this module."
  type        = map(object({ purpose = string }))
}
