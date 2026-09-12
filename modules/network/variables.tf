variable "name" {
  description = "name for this module."
  type        = string
}

variable "vpc_cidr" {
  description = "vpc cidr for this module."
  type        = string
}

variable "public_subnets" {
  description = "public subnets for this module."
  type        = map(object({ cidr_block = string, availability_zone = string }))
}

variable "private_subnets" {
  description = "private subnets for this module."
  type        = map(object({ cidr_block = string, availability_zone = string }))
}
