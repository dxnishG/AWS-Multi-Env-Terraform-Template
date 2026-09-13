locals {
  name = "${var.name_prefix}-${var.environment}"
}
module "network" {
  source          = "./modules/network"
  name            = local.name
  vpc_cidr        = var.vpc_cidr
  public_subnets  = var.public_subnet_configs
  private_subnets = var.private_subnet_configs
}
module "storage" {
  source  = "./modules/storage"
  name    = local.name
  buckets = var.s3_buckets
}
module "service" {
  source                     = "./modules/service"
  name                       = local.name
  vpc_id                     = module.network.vpc_id
  public_subnet_ids          = values(module.network.public_subnet_ids)
  private_subnet_ids         = values(module.network.private_subnet_ids)
  ami_id                     = var.ami_id
  certificate_arn            = var.certificate_arn
  instance_type              = var.instance_type
  app_port                   = var.app_port
  health_check_path          = var.health_check_path
  min_size                   = var.min_size
  max_size                   = var.max_size
  alarm_topic_arn            = var.alarm_topic_arn
  bucket_arns                = module.storage.bucket_arns
  bucket_kms_key_arn         = module.storage.kms_key_arn
  enable_deletion_protection = var.enable_deletion_protection
  tags                       = merge(var.tags, { Environment = var.environment, ManagedBy = "Terraform" })
  depends_on                 = [module.network]
}
module "recovery" {
  source          = "./modules/recovery"
  name            = local.name
  alarm_topic_arn = var.alarm_topic_arn
}
