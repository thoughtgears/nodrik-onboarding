# Example: single project

The smallest working use of [`../../terraform`](../../terraform) — one
project, one tenant service account, one topic.

```bash
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars with the values Nodrik gave you
terraform init
terraform plan
```

See [`../../terraform/README.md`](../../terraform/README.md) for what
`plan` will show and what each output means.
