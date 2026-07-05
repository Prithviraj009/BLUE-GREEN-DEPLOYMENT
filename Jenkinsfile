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
        AWS_CRED_ID    = 'aws-cred-admin'
        KUBE_CRED_ID   = 'k8-token'
    }

    stages {

        stage('Validate Params') {
            steps {
                script {
                    if (params.DEPLOY_ENV != params.DOCKER_TAG) {
                        error "DEPLOY_ENV (${params.DEPLOY_ENV}) and DOCKER_TAG (${params.DOCKER_TAG}) must match"
                    }
                }
            }
        }

        // we use dir() as the Dockerfile is in the app folder, so it runs docker build in app dir
        stage('Build & Push Image') {
            steps {
                dir('app') {
                    script {
                        withDockerRegistry(credentialsId: 'docker-cred') {
                            sh "docker build -t ${IMAGE_NAME}:${TAG} ."
                            sh "docker push ${IMAGE_NAME}:${TAG}"
                        }
                    }
                }
            }
        }

        stage('Deploy to Kubernetes') {
            steps {
                script {
                    def deploymentManifest = "kubernetes/deployment/${params.DEPLOY_ENV}-deployment.yaml"

                    withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: "${AWS_CRED_ID}"]]) {
                        withKubeConfig(credentialsId: "${KUBE_CRED_ID}", namespace: "${KUBE_NAMESPACE}") {
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
        }

        stage('Smoke Test') {
        steps {
            withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: "${AWS_CRED_ID}"]]) {
                withKubeConfig(credentialsId: "${KUBE_CRED_ID}", namespace: "${KUBE_NAMESPACE}") {
                    sh """
                        kubectl run smoke-test-${BUILD_NUMBER} --rm -i --restart=Never \\
                        --image=curlimages/curl -n ${KUBE_NAMESPACE} \\
                        -- curl -f http://service-bg-preview.${KUBE_NAMESPACE}.svc.cluster.local/health
                    """
                }
            }
        }
}
        stage('Switch Traffic') {
            when {
                expression { return params.SWITCH_TRAFFIC }
            }
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: "${AWS_CRED_ID}"]]) {
                    withKubeConfig(credentialsId: "${KUBE_CRED_ID}", namespace: "${KUBE_NAMESPACE}") {
                        sh """
                            kubectl patch service service-bg-active -n ${KUBE_NAMESPACE} --type merge -p '{"spec":{"selector":{"app":"bg-app","version":"${params.DEPLOY_ENV}"}}}'
                        """
                    }
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