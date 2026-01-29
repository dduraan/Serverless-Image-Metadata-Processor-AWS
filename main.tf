# 1.proveedor
provider "aws" {
  region = "eu-south-2"
}

# 2.Crear los Buckets de S3
resource "aws_s3_bucket" "imagenes_input" {
  bucket = "proyecto-aws-saa-victorduran-input"
}

resource "aws_s3_bucket" "imagenes_output" {
  bucket = "proyecto-aws-saa-victorduran-output"
}

# 3.Crear la tabla de DynamoDB
resource "aws_dynamodb_table" "metadatos_imagenes" {
  name         = "LogImagenes"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "ImageID"

  attribute {
    name = "ImageID"
    type = "S"
  }
}


resource "aws_lambda_function" "mi_lambda" {
  # Ahora apunta directamente al archivo en la raiz
  filename         = "index.zip" 
  function_name    = "procesador_imagenes"
  role             = aws_iam_role.iam_for_lambda.arn
  handler          = "index.handler"
  runtime          = "python3.9"

  # El hash tambien debe apuntar al archivo en la raiz
  source_code_hash = filebase64sha256("index.zip")
}


# Crear el rol para la Lambda
resource "aws_iam_role" "iam_for_lambda" {
  name = "iam_for_lambda"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

# Darle permisos básicos de ejecución (Logs en CloudWatch)
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.iam_for_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Darle permisos para leer de S3 y escribir en DynamoDB
resource "aws_iam_role_policy" "lambda_permissions" {
  name = "lambda_permissions"
  role = aws_iam_role.iam_for_lambda.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject"],
      "Resource": ["${aws_s3_bucket.imagenes_input.arn}/*"]
    },
    {
      "Effect": "Allow",
      "Action": ["dynamodb:PutItem"],
      "Resource": ["${aws_dynamodb_table.metadatos_imagenes.arn}"]
    }
  ]
}
EOF
}

# 1. EL PERMISO
resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.mi_lambda.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.imagenes_input.arn
}

# 2. EL DISPARADOR
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.imagenes_input.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.mi_lambda.arn
    events              = ["s3:ObjectCreated:*"]
  }
  
  # Importante: Primero dar el permiso y luego configurar la notificacion
  depends_on = [aws_lambda_permission.allow_s3]
}

