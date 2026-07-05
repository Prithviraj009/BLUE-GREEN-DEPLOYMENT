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
    }

    stages {

      
        //we used dir as dockerfile is in app folder so it executes the command in app dir

       stage('Build Image') {
        steps {
            dir('app') {
                script {
                    withDockerRegistry(credentialsId: 'docker-cred') {
                        sh "docker build -t ${IMAGE_NAME}:${TAG} ."
                    }
                }
            }
        }
}

        stage('Push Image') {
            steps {
                script {
                    withDockerRegistry(credentialsId: 'docker-cred') {
                        sh "docker build -t ${IMAGE_NAME}:${TAG} -f app/Dockerfile app"
                    }
                }
            }
        }

        stage('Deploy to Kubernetes') {
            steps {
                script {
                    def deploymentManifest = "kubernetes/deployment/${params.DEPLOY_ENV}-deployment.yaml"

                    withKubeConfig(credentialsId: 'k8-token', namespace: "${KUBE_NAMESPACE}") {
                        sh """
                            kubectl create namespace ${KUBE_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
                            kubectl apply -f kubernetes/services/service-bg-active.yaml -f kubernetes/services/service-bg-preview.yaml -n ${KUBE_NAMESPACE}
                            kubectl apply -f ${deploymentManifest} -n ${KUBE_NAMESPACE}
                            kubectl set image deployment/deployment-${params.DEPLOY_ENV} app=${IMAGE_NAME}:${TAG} -n ${KUBE_NAMESPACE}
                            kubectl rollout status deployment/deployment-${params.DEPLOY_ENV} -n ${KUBE_NAMESPACE} --timeout=180s
                            kubectl patch service service-bg-preview -n ${KUBE_NAMESPACE} --type merge -p '{"spec":{"selector":{"app":"bg-app","version":"${params.DEPLOY_ENV}"}}}'
                        """
                    }
                }
            }
        }

        stage('Smoke Test') {
            steps {
                withKubeConfig(credentialsId: 'k8-token', namespace: "${KUBE_NAMESPACE}") {
                    sh """
                        kubectl port-forward svc/service-bg-preview 18080:80 -n ${KUBE_NAMESPACE} &
                        PF_PID=\$!
                        sleep 5
                        curl -f http://localhost:18080/health || (kill \$PF_PID && exit 1)
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
                        kubectl patch service service-bg-active -n ${KUBE_NAMESPACE} --type merge -p '{"spec":{"selector":{"app":"bg-app","version":"${params.DEPLOY_ENV}"}}}'
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
