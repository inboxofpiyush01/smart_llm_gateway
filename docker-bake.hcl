variable "IMAGE" {
  default = "piyushdocker90/smart-llm-gateway:latest"
}

group "default" {
  targets = ["app"]
}

target "app" {
  context = "."
  dockerfile = "Dockerfile"
  tags = [IMAGE]
  platforms = ["linux/amd64"]
}
