output "api_endpoint" {
    value = "http://${aws_api_gateway_rest_api.rest.id}.execute-api.localhost.localstack.cloud:4566/${aws_api_gateway_deployment.deployment.stage_name}/ingest"
}

output "lambda_function" {
    value = aws_lambda_function.consumer.function_name
}