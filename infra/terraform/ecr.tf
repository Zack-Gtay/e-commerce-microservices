# One repository per service, generated from local.services.

resource "aws_ecr_repository" "this" {
  for_each = local.services

  name                 = "eshop/${each.key}"
  image_tag_mutability = "IMMUTABLE" # a given SHA tag can never be repointed

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

# Keep the last 30 tagged images and expire untagged layers quickly, so the registry does
# not grow without bound as every merge to main pushes a new SHA.
resource "aws_ecr_lifecycle_policy" "this" {
  for_each = aws_ecr_repository.this

  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only the 30 most recent tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v", "latest", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f"]
          countType     = "imageCountMoreThan"
          countNumber   = 30
        }
        action = { type = "expire" }
      }
    ]
  })
}
