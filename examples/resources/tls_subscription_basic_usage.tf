terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.55.0"
    }
    fastly = {
      source  = "fastly/fastly"
      version = "3.1.0"
    }
  }
}

# NOTE: Creating a hosted zone will automatically create SOA/NS records.
resource "aws_route53_zone" "production" {
  name = "example.com"
}

resource "aws_route53domains_registered_domain" "example" {
  domain_name = "example.com"

  dynamic "name_server" {
    for_each = aws_route53_zone.production.name_servers

    content {
      name = name_server.value
    }
  }
}

locals {
  subdomains = [
    "a.example.com",
    "b.example.com",
  ]
}

resource "fastly_service_vcl" "example" {
  name = "example-service"

  dynamic "domain" {
    for_each = local.subdomains

    content {
      name = domain.value
    }
  }

  backend {
    address = "127.0.0.1"
    name    = "localhost"
  }

  force_destroy = true
}

resource "fastly_tls_subscription" "testing_tls" {
  domains               = [for domain in fastly_service_vcl.testing-tls.domain : domain.name]
  certificate_authority = "lets-encrypt"
}

resource "aws_route53_record" "domain_validation" {
  depends_on = [fastly_tls_subscription.testing_tls]

  for_each = {
    # The following `for` expression (due to the outer {}) will produce an object with key/value pairs.
    # The 'key' is the domain name we've configured (e.g. a.example.com, b.example.com)
    # The 'value' is a specific 'challenge' object whose record_name matches the domain (e.g. record_name is _acme-challenge.a.example.com).
    for domain in fastly_tls_subscription.testing_tls.domains :
    domain => element([
      for obj in fastly_tls_subscription.testing_tls.managed_dns_challenges :
      obj if obj.record_name == "_acme-challenge.${domain}" # We use an `if` conditional to filter the list to a single element
    ], 0)                                                   # `element()` returns the first object in the list which should be the relevant 'challenge' object we need
  }

  name            = each.value.record_name
  type            = each.value.record_type
  zone_id         = aws_route53_zone.production.zone_id
  allow_overwrite = true
  records         = [each.value.record_value]
  ttl             = 60
}

# This is a resource that other resources can depend on if they require the certificate to be issued.
# NOTE: Internally the resource keeps retrying `GetTLSSubscription` until no error is returned (or the configured timeout is reached).
resource "fastly_tls_subscription_validation" "testing_tls" {
  subscription_id = fastly_tls_subscription.testing_tls.id
  depends_on      = [aws_route53_record.domain_validation]
}

# This data source lists all configuration and uses the `default` attribute to narrow down the configuration to just one object.
# If the filtered list has a length that is not exactly one element, you'll see an error returned.
# That single TLS configuration element is then returned.
data "fastly_tls_configuration" "default_tls" {
  default    = true
  depends_on = [fastly_tls_subscription_validation.testing_tls]
}

# Once validation is complete and we've retrieved the TLS configuration data, we can create multiple subdomain records.
resource "aws_route53_record" "subdomain" {
  for_each = toset(local.subdomains) # Because `subdomains` is ultimately a list, the `each` variable produced will contain only a `value` property which will be the subdomain.

  name    = each.value # e.g. a.example.com, b.example.com
  records = [for record in data.fastly_tls_configuration.default_tls.dns_records : record.record_value if record.record_type == "CNAME"]
  ttl     = 300
  type    = "CNAME"
  zone_id = aws_route53_zone.production.zone_id
}
