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
  default = {
    web-1a = { cidr_block = "10.0.1.0/24", availability_zone = "us-east-1a" }
    web-1b = { cidr_block = "10.0.2.0/24", availability_zone = "us-east-1b" }
  }
}

variable "private_subnets" {
  description = "private subnets for this module."
  type        = map(object({ cidr_block = string, availability_zone = string }))
  default = {
    app-1a = { cidr_block = "10.0.10.0/24", availability_zone = "us-east-1a" }
    app-1b = { cidr_block = "10.0.20.0/24", availability_zone = "us-east-1b" }
  }
}
