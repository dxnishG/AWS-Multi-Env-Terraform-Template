variable "name" {
  description = "name for this module."
  type        = string
}

variable "vpc_id" {
  description = "vpc id for this module."
  type        = string
}

variable "public_subnet_ids" {
  description = "public subnet ids for this module."
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "private subnet ids for this module."
  type        = list(string)
}

variable "ami_id" {
  description = "ami id for this module."
  type        = string
}

variable "certificate_arn" {
  description = "certificate arn for this module."
  type        = string
}

variable "instance_type" {
  description = "instance type for this module."
  type        = string
}

variable "app_port" {
  description = "app port for this module."
  type        = number
}

variable "health_check_path" {
  description = "health check path for this module."
  type        = string
}

variable "min_size" {
  description = "min size for this module."
  type        = number
}

variable "max_size" {
  description = "max size for this module."
  type        = number
}

variable "alarm_topic_arn" {
  description = "alarm topic arn for this module."
  type        = string
}

variable "bucket_arns" {
  description = "bucket arns for this module."
  type        = map(string)
}

variable "bucket_kms_key_arn" {
  description = "bucket kms key arn for this module."
  type        = string
}

variable "tags" {
  description = "tags for this module."
  type        = map(string)
}
