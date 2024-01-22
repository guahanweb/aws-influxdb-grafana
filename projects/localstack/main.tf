data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_api_gateway_rest_api" "rest" {
    name = "${var.project_name}-rest_api"
}

resource "aws_api_gateway_resource" "ingest" {
    rest_api_id = aws_api_gateway_rest_api.rest.id
    parent_id = aws_api_gateway_rest_api.rest.root_resource_id
    path_part = "{ingest}"
}

resource "aws_api_gateway_method" "method" {
    rest_api_id = aws_api_gateway_rest_api.rest.id
    resource_id = aws_api_gateway_resource.ingest.id
    http_method = "POST"
    authorization = "NONE"
    request_models = {
        "application/json" = aws_api_gateway_model.model.name
    }
    request_validator_id = aws_api_gateway_request_validator.validator.id
}

resource "aws_api_gateway_model" "model" {
    rest_api_id = aws_api_gateway_rest_api.rest.id
    name = "packet"
    description = "packet format"
    content_type = "application/json"

    schema = <<EOF
        {
            "$schema": "http://json-schema.org/draft-04/schema#",
            "title": "EventRecord",
            "type": "object",
            "properties": {
                "event": {
                    "type": "object",
                    "properties": {
                        "type": { "type": "string" },
                        "name": { "type": "string" },
                        "value": { "type": ["string","number","boolean"] },
                        "timestamp": { "type": "number" },
                        "meta": { "type": "object" }
                    },
                    "required": ["type", "name", "value", "timestamp"],
                    "additionalProperties": true
                }
            }
        }
    EOF
}

resource "aws_api_gateway_request_validator" "validator" {
    name = "${var.project_name}-validator"
    rest_api_id = aws_api_gateway_rest_api.rest.id
    validate_request_body = true
    validate_request_parameters = true
}

resource "aws_iam_role" "apigw-role" {
    name = "${var.project_name}-api_gateway_invocation"
    assume_role_policy = <<-EOF
        {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Sid": "",
                    "Effect": "Allow",
                    "Principal": {
                        "Service": "apigateway.amazonaws.com"
                    },
                    "Action": "sts:AssumeRole"
                }
            ]
        }
    EOF
}

resource "aws_iam_policy" "put-record-policy" {
    name = "${var.project_name}-put_record_policy"
    policy = <<-POLICY
        {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Action": "kinesis:PutRecord",
                    "Resource": "arn:aws:kinesis:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:stream/${aws_kinesis_stream.stream.name}"
                }
            ]
        }
    POLICY
}

resource "aws_iam_role_policy_attachment" "apigwy_policy" {
    role = aws_iam_role.apigw-role.name
    policy_arn = aws_iam_policy.put-record-policy.arn
}

resource "aws_api_gateway_integration" "integration" {
    rest_api_id = aws_api_gateway_rest_api.rest.id
    resource_id = aws_api_gateway_resource.ingest.id
    http_method = aws_api_gateway_method.method.http_method
    integration_http_method = "POST"
    type = "AWS"
    credentials = aws_iam_role.apigw-role.arn
    uri = "arn:aws:apigateway:${data.aws_region.current.name}:kinesis:action/PutRecord"

    passthrough_behavior = "NEVER"

    request_parameters = {
      "integration.request.header.Content-Type" = "'application/x-amz-json-1.1'"
    }

    request_templates = {
        "application/json" = <<EOT
            {
                "Data": "$util.base64Encode($input.body)",
                "PartitionKey": "$util.escapeJavaScript($input.params('ingest'))",
                "StreamName": "${aws_kinesis_stream.stream.name}"
            }
        EOT
    }
}

resource "aws_api_gateway_method_response" "status_code_200" {
    http_method = aws_api_gateway_method.method.http_method
    resource_id = aws_api_gateway_resource.ingest.id
    rest_api_id = aws_api_gateway_rest_api.rest.id
    status_code = 200

    response_parameters = {
      "method.response.header.Content-Type" = true
      "method.response.header.Access-Control-Allow-Origin" = true
    }
}

resource "aws_api_gateway_method_response" "status_code_400" {
    http_method = aws_api_gateway_method.method.http_method
    resource_id = aws_api_gateway_resource.ingest.id
    rest_api_id = aws_api_gateway_rest_api.rest.id
    status_code = 400

    response_parameters = {
      "method.response.header.Content-Type" = true
      "method.response.header.Access-Control-Allow-Origin" = true
    }
}

resource "aws_api_gateway_integration_response" "integration_success_response" {
    rest_api_id = aws_api_gateway_rest_api.rest.id
    resource_id = aws_api_gateway_resource.ingest.id
    http_method = aws_api_gateway_method.method.http_method
    status_code = aws_api_gateway_method_response.status_code_200.status_code

    response_parameters = {
      "method.response.header.Content-Type" = "'application/json'"
      "method.response.header.Access-Control-Allow-Origin" = "'*'"
    }

    response_templates = {
      "application/json" = <<EOT
        {
            "state": "ok"
        }
      EOT
    }

    depends_on = [ aws_api_gateway_integration.integration ]
}

resource "aws_api_gateway_integration_response" "integration_error_response" {
    rest_api_id = aws_api_gateway_rest_api.rest.id
    resource_id = aws_api_gateway_resource.ingest.id
    http_method = aws_api_gateway_method.method.http_method
    status_code = aws_api_gateway_method_response.status_code_400.status_code

    selection_pattern = "4\\d{2}"

    response_parameters = {
      "method.response.header.Content-Type" = "'application/json'"
      "method.response.header.Access-Control-Allow-Origin" = "'*'"
    }

    response_templates = {
      "application/json" = <<EOT
        {
            "state": "error",
            "mesage": "$util.escapeJavaScript($input.path('$.errorMessage'))"
        }
      EOT
    }

    depends_on = [ aws_api_gateway_integration.integration ]
}

resource "aws_api_gateway_deployment" "deployment" {
    rest_api_id = aws_api_gateway_rest_api.rest.id
    stage_name = "dev"
    depends_on = [ aws_api_gateway_integration.integration ]
}

resource "aws_kinesis_stream" "stream" {
    name = "${var.project_name}-timeseries-ingest-stream"
    shard_count = "3"

    retention_period = 30

    shard_level_metrics = [
        "IncomingBytes",
        "OutgoingBytes",
        "OutgoingRecords",
        "ReadProvisionedThroughputExceeded",
        "WriteProvisionedThroughputExceeded",
        "IncomingRecords",
        "IteratorAgeMilliseconds",
    ]
}

resource "aws_iam_role" "role" {
    name = "${var.project_name}-iam_role"
    path = "/"
    managed_policy_arns = ["arn:aws:iam::aws:policy/AmazonKinesisFullAccess"]
    assume_role_policy = <<POLICY
        {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Sid": "",
                    "Action": "sts:AssumeRole",
                    "Principal": {
                        "Service": "lambda.amazonaws.com"
                    },
                    "Effect": "Allow"
                }
            ]
        }
    POLICY
}

resource "aws_iam_policy" "function_logging_policy" {
  name   = "${var.project_name}-function_logging_policy"
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        Action : [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Effect : "Allow",
        Resource : "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "function_logging" {
    role = aws_iam_role.role.name
    policy_arn = aws_iam_policy.function_logging_policy.arn
}

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/consumer"
  retention_in_days = 7
  lifecycle {
    prevent_destroy = false
  }
}

# Lambda consumer
resource "aws_lambda_function" "consumer" {
    filename      = "${var.function_path}/aws-kinesis-consumer/1.0.0.zip"
    function_name = "consumer"
    role          = aws_iam_role.role.arn
    handler       = "index.handler"
    depends_on = [ aws_cloudwatch_log_group.lambda_log_group ]

    source_code_hash = filebase64sha256("${var.function_path}/aws-kinesis-consumer/1.0.0.zip")

    # LocalStack only supports up to Node.js 16
    # runtime = "nodejs20.x"
    runtime = "nodejs16.x"

    environment {
        variables = {
            TIMESTAMP_PRECISION = "ms"
            INFLUXDB_URL = "http://host.docker.internal:8086"
            INFLUXDB_ORG = "vrlabs"
            INFLUXDB_BUCKET = "telemetry"
            INFLUXDB_TOKEN = var.influxdb_token
        }
    }
}

# Push to lambda from Kinesis stream
resource "aws_lambda_event_source_mapping" "example" {
  event_source_arn  = aws_kinesis_stream.stream.arn
  function_name     = aws_lambda_function.consumer.arn
  starting_position = "LATEST"
  batch_size        = 5
  enabled           = true
}
