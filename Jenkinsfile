pipeline {
    agent any

    environment {
        AWS_REGION       = 'us-east-2'
        AWS_ACCOUNT_ID   = '781707116910'
        ECR_REPO         = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/be-historic-export-runner"
        ECS_CLUSTER      = 'be-historic-export-cluster'
        ECS_TASK_DEF     = 'be-historic-export-task'
        S3_BUCKET        = "be-historic-export-data-prod-${AWS_ACCOUNT_ID}"
        SUBNETS          = 'subnet-887db4e0,subnet-47060b3c'
        SECURITY_GROUP   = 'sg-0682c6b797b62d1d8'
        IMAGE_TAG        = "v${BUILD_NUMBER}"
        // Slack or email notification target
        NOTIFY_CHANNEL   = '#weekly-test'
    }

    options {
        timestamps()
        timeout(time: 60, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '20'))
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Build Docker Image') {
            steps {
                dir('docker') {
                    sh """
                        docker build --no-cache --platform linux/amd64 \
                            -t be-historic-export-runner:${IMAGE_TAG} .
                    """
                }
            }
        }

        stage('Push to ECR') {
            steps {
                sh """
                    aws ecr get-login-password --region ${AWS_REGION} | \
                        docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

                    docker tag be-historic-export-runner:${IMAGE_TAG} ${ECR_REPO}:${IMAGE_TAG}
                    docker push ${ECR_REPO}:${IMAGE_TAG}
                """
            }
        }

        stage('Update Task Definition') {
            steps {
                dir('.') {
                    sh """
                        sed -i 's/image_tag = "v[0-9]*"/image_tag = "${IMAGE_TAG}"/' terraform.tfvars
                        terraform init -input=false
                        terraform apply -auto-approve -input=false
                    """
                }
            }
        }

        stage('Trigger Export') {
            steps {
                script {
                    def runOutput = sh(
                        script: """
                            aws ecs run-task \
                                --cluster ${ECS_CLUSTER} \
                                --task-definition ${ECS_TASK_DEF} \
                                --launch-type FARGATE \
                                --network-configuration "awsvpcConfiguration={subnets=[${SUBNETS}],securityGroups=[${SECURITY_GROUP}],assignPublicIp=ENABLED}" \
                                --region ${AWS_REGION} \
                                --query 'tasks[0].taskArn' \
                                --output text
                        """,
                        returnStdout: true
                    ).trim()
                    env.TASK_ARN = runOutput
                }
                echo "Task started: ${TASK_ARN}"
            }
        }

        stage('Wait for Completion') {
            steps {
                script {
                    def taskId = env.TASK_ARN.split('/').last()
                    def status = 'RUNNING'
                    def attempts = 0
                    def maxAttempts = 60 // 30 minutes max

                    while (status != 'STOPPED' && attempts < maxAttempts) {
                        sleep(30)
                        status = sh(
                            script: """
                                aws ecs describe-tasks \
                                    --cluster ${ECS_CLUSTER} \
                                    --tasks ${TASK_ARN} \
                                    --region ${AWS_REGION} \
                                    --query 'tasks[0].lastStatus' \
                                    --output text
                            """,
                            returnStdout: true
                        ).trim()
                        attempts++
                        echo "Task status: ${status} (check ${attempts}/${maxAttempts})"
                    }

                    // Check exit code
                    def exitCode = sh(
                        script: """
                            aws ecs describe-tasks \
                                --cluster ${ECS_CLUSTER} \
                                --tasks ${TASK_ARN} \
                                --region ${AWS_REGION} \
                                --query 'tasks[0].containers[0].exitCode' \
                                --output text
                        """,
                        returnStdout: true
                    ).trim()

                    if (exitCode != '0') {
                        error "Export task failed with exit code: ${exitCode}"
                    }
                }
            }
        }

        stage('Get S3 Output') {
            steps {
                script {
                    // Find the latest export folder
                    env.EXPORT_PATH = sh(
                        script: """
                            aws s3 ls s3://${S3_BUCKET}/exports/ --region ${AWS_REGION} | \
                                sort | tail -1 | awk '{print \$2}'
                        """,
                        returnStdout: true
                    ).trim()

                    env.S3_URL = "s3://${S3_BUCKET}/exports/${EXPORT_PATH}"
                    env.CONSOLE_URL = "https://s3.console.aws.amazon.com/s3/buckets/${S3_BUCKET}?region=${AWS_REGION}&prefix=exports/${EXPORT_PATH}"

                    // List files
                    env.FILE_LIST = sh(
                        script: """
                            aws s3 ls s3://${S3_BUCKET}/exports/${EXPORT_PATH} --recursive --region ${AWS_REGION}
                        """,
                        returnStdout: true
                    ).trim()
                }
                echo "Export output: ${S3_URL}"
            }
        }
    }

    post {
        success {
            slackSend(
                channel: "${NOTIFY_CHANNEL}",
                color: 'good',
                message: """*BE Historic Export — Complete*
Build: #${BUILD_NUMBER}
Image: `${ECR_REPO}:${IMAGE_TAG}`

*Download your data:*
S3 Path: `${env.S3_URL}`
Console: ${env.CONSOLE_URL}

*CLI Download:*
```
aws s3 sync ${env.S3_URL} ./export-data/ --region ${AWS_REGION}
```

*Files:*
```
${env.FILE_LIST}
```"""
            )
        }
        failure {
            slackSend(
                channel: "${NOTIFY_CHANNEL}",
                color: 'danger',
                message: """*BE Historic Export — FAILED*
Build: #${BUILD_NUMBER}
Check logs: `aws logs tail /ecs/be-historic-export --follow --region ${AWS_REGION}`
Jenkins: ${BUILD_URL}"""
            )
        }
        always {
            sh 'docker rmi be-historic-export-runner:${IMAGE_TAG} || true'
        }
    }
}
