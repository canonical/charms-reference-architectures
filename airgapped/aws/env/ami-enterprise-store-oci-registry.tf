# Copyright 2025 Canonical Ltd.
# See LICENSE file for licensing details.

locals {
  ENTERPRISE_STORE_OCI_REGISTRY = "snapstore-proxy-oci-registry"
  estore_ociregistry_steps      = [
    {
      name      = "UpdateAndInstallPackages"
      script    = "scripts/snapstore-proxy-oci-registry/ami-install-packages.sh"
    },
    {
      name      = "SetupPostgres"
      script    = "scripts/snapstore-proxy-oci-registry/ami-setup-postgres.sh"
    },
    {
      name      = "SetupSnapStoreProxy"
      script    = "scripts/snapstore-proxy-oci-registry/ami-setup-store.sh"
    },
    {
      name      = "SetupOCIRegistry"
      script    = "scripts/snapstore-proxy-oci-registry/ami-setup-oci-registry.sh"
    },
    {
      name      = "ExportCharmResources"
      script    = "scripts/snapstore-proxy-oci-registry/ami-export-load-resources.sh"
    }
  ]
}

resource "aws_imagebuilder_component" "estore_ociregistry_component" {
  name        = "${local.ENTERPRISE_STORE_OCI_REGISTRY}-component"
  description = "The build component of the image."
  platform    = "Linux"
  version     = "1.0.0"

  data = yamlencode({
    name          = "setup-${local.ENTERPRISE_STORE_OCI_REGISTRY}-env"
    description   = "Install dependencies and setup the snapstore-proxy / oci-registry environment."
    schemaVersion = "1.0"
    phases = [
      {
        name  = "build"
        steps = concat(
          [
            {
              name      = "DownloadScriptsAndResourcesFromS3"
              action    = "ExecuteBash"
              onFailure = "Abort"
              inputs = {
                commands = [
                  "snap install aws-cli --classic",
                  "aws s3 cp s3://${aws_s3_bucket.imagebuilder_scripts_bucket.bucket}/scripts/${local.ENTERPRISE_STORE_OCI_REGISTRY}/ /tmp/ --recursive"
                ]
              }
            },
          ],
          [
            for step in local.estore_ociregistry_steps : {
              name      = step.name
              action    = "ExecuteBash"
              onFailure = "Abort"
              inputs = {
                commands = [
                  "chmod +x /tmp/${basename(step.script)} && bash /tmp/${basename(step.script)}"
                ]
              }
            }
          ]
        )
      }
    ]
  })

  depends_on = [
    aws_s3_object.imagebuilder_scripts
  ]
}

resource "aws_imagebuilder_image_recipe" "estore_ociregistry_image_recipe" {
  name         = "${local.ENTERPRISE_STORE_OCI_REGISTRY}-image-recipe"
  version      = "1.0.0"
  parent_image = "arn:aws:imagebuilder:${var.region}:aws:image/ubuntu-server-22-lts-x86/x.x.x"
  # Use the latest Ubuntu AMI

  block_device_mapping {
    device_name = "/dev/sda1"
    ebs {
      volume_size           = 75
      volume_type           = "gp2"
      delete_on_termination = true
    }
  }

  component {
    component_arn = aws_imagebuilder_component.estore_ociregistry_component.arn
  }
}

resource "aws_imagebuilder_infrastructure_configuration" "estore_ociregistry_infra_config" {
  name                          = "${local.ENTERPRISE_STORE_OCI_REGISTRY}-infra-config"
  instance_profile_name         = aws_iam_instance_profile.imagebuilder_profile.name
  terminate_instance_on_failure = true
  instance_types = ["t3.medium"]
}

resource "aws_imagebuilder_image_pipeline" "estore_ociregistry_pipeline" {
  name                             = "${local.ENTERPRISE_STORE_OCI_REGISTRY}-pipeline"
  image_recipe_arn                 = aws_imagebuilder_image_recipe.estore_ociregistry_image_recipe.arn
  infrastructure_configuration_arn = aws_imagebuilder_infrastructure_configuration.estore_ociregistry_infra_config.arn
}

resource "aws_imagebuilder_distribution_configuration" "estore_ociregistry_dist_config" {
  name = "${local.ENTERPRISE_STORE_OCI_REGISTRY}-image-distribution"

  distribution {
    region = var.region

    ami_distribution_configuration {
      name        = "${local.ENTERPRISE_STORE_OCI_REGISTRY}-{{ imagebuilder:buildDate }}"
      description = "AMI of snapstore proxy / oci-registry for air-gapped deployments."
    }
  }
}

resource "aws_imagebuilder_image" "estore_ociregistry_image" {
  image_recipe_arn                 = aws_imagebuilder_image_recipe.estore_ociregistry_image_recipe.arn
  infrastructure_configuration_arn = aws_imagebuilder_infrastructure_configuration.estore_ociregistry_infra_config.arn
  distribution_configuration_arn   = aws_imagebuilder_distribution_configuration.estore_ociregistry_dist_config.arn
}

