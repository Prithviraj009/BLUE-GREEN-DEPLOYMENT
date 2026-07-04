pipeline {
    agent any

    parameters {
        choice(name: 'DEPLOY_ENV', choices: ['blue', 'green'], description: 'Select the environment to deploy')
        choice(name: 'DOCKER_TAG', choices: ['blue', 'green'], description: 'Select the docker tag to deploy')
        booleanParam(name: 'SWITCH_TRAFFIC', defaultValue: false, description: 'Switch traffic between blue and green')
    }

    environment {
        IMAGE_NAME     = "snowman0000/bg-deployment"
        TAG            = "${params.DOCKER_TAG}"
        KUBE_NAMESPACE = 'webapps'
        SCANNER_HOME   = tool 'sonar-scanner'
    }

    stages {

        stage('Checkout') {
            steps {
                git branch: 'main', url: 'https://github.com/Prithviraj009/Blue-Green-Deployment.git'
            }
        }

        stage('SonarQube Analysis') {
            steps {
                withSonarQubeEnv('sonar') {
                    sh """
                        ${SCANNER_HOME}/bin/sonar-scanner \
                        -Dsonar.projectName=bg-deployment \
                        -Dsonar.projectKey=bg-deployment
                    """
                }
            }
        }

        stage('Quality Gate') {
            steps {
                timeout(time: 5, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        stage('OWASP Dependency Check') {
            steps {
                dependencyCheck additionalArguments: '--scan . --format ALL --disableYarnAudit', odcInstallation: 'OWASP-DC'
                dependencyCheckPublisher pattern: '**/dependency-check-report.xml'
            }
        }

        stage('Build Image') {
            steps {
                script {
                    withDockerRegistry(credentialsId: 'docker-cred') {
                        sh "docker build -t ${IMAGE_NAME}:${TAG} ."
                    }
                }
            }
        }

        stage('Trivy Image Scan') {
            steps {
                sh """
                    trivy image --exit-code 0 --severity LOW,MEDIUM ${IMAGE_NAME}:${TAG} || true
                    trivy image --exit-code 1 --severity HIGH,CRITICAL ${IMAGE_NAME}:${TAG}
                """
            }
        }

        stage('Push Image') {
            steps {
                script {
                    withDockerRegistry(credentialsId: 'docker-cred') {
                        sh "docker push ${IMAGE_NAME}:${TAG}"
                    }
                }
            }
        }

        stage('Deploy to Kubernetes') {
            steps {
                script {
                    def deploymentFile = (params.DEPLOY_ENV == 'blue') ? 'blue-deployment.yaml' : 'green-deployment.yaml'

                    withKubeConfig(credentialsId: 'k8-token', namespace: "${KUBE_NAMESPACE}") {
                        sh "kubectl apply -f ${deploymentFile} -n ${KUBE_NAMESPACE}"
                        sh "kubectl rollout status deployment/deployment-${params.DEPLOY_ENV} -n ${KUBE_NAMESPACE} --timeout=120s"
                    }
                }
            }
        }

        stage('Smoke Test') {
            steps {
                withKubeConfig(credentialsId: 'k8-token', namespace: "${KUBE_NAMESPACE}") {
                    sh """
                        kubectl port-forward deployment/deployment-${params.DEPLOY_ENV} 18080:8080 -n ${KUBE_NAMESPACE} &
                        PF_PID=\$!
                        sleep 5
                        curl -f http://localhost:18080/ || (kill \$PF_PID && exit 1)
                        kill \$PF_PID
                    """
                }
            }
        }

        stage('Switch Traffic') {
            when {
                expression { return params.SWITCH_TRAFFIC }
            }
            steps {
                withKubeConfig(credentialsId: 'k8-token', namespace: "${KUBE_NAMESPACE}") {
                    sh """
                        kubectl patch service service-bg -n ${KUBE_NAMESPACE} \
                            -p '{"spec":{"selector":{"app":"service-${params.DEPLOY_ENV}"}}}'
                    """
                }
                echo "Traffic switched to ${params.DEPLOY_ENV}"
            }
        }
    }

    post {
        success {
            echo "Pipeline finished. Deployed ${params.DEPLOY_ENV}. Traffic switched: ${params.SWITCH_TRAFFIC}"
        }
        failure {
            echo "Pipeline failed — check stage logs above."
        }
    }
}
