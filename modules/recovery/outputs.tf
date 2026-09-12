output "vault_name" {
  description = "vault name produced by this module."
  value       = aws_backup_vault.this.name
}
