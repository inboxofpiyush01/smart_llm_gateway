# AnyCloud Studio - shared local/production Kubernetes deployment
param(
  [ValidateSet('local','production')][string]$Mode = 'production',
  [string]$Name = 'smart-llm-gateway',
  [string]$Image = 'piyushdocker90/smart-llm-gateway:latest',
  [int]$ContainerPort = 8501,
  [string]$Kubeconfig = '',
  [string]$Context = 'smart-llm-gateway',
  [string]$Namespace = 'default',
  [ValidateSet('loadbalancer','ingress')][string]$Exposure = 'loadbalancer',
  [string]$IngressHost = '',
  [string]$ImagePullSecret = '',
  [string]$TlsSecret = '',
  [string]$RegistryType = 'dockerhub',
  [string]$RegistryUrl = '',
  [string]$RegistryUsername = 'piyushdocker90',
  [string]$RegistryRegion = '',
  [string]$RegistryProject = '',
  [string]$RegistryName = '',
  [string]$RegistryProfile = '',
  [string]$ArtifactRepository = '',
  [string]$Repository = 'piyushdocker90/smart-llm-gateway',
  [string]$ImageTag = 'latest',
  [string]$CreateNamespace = 'true',
  [string]$EnableHpa = 'true',
  [string]$HealthPath = '/'
)
$ErrorActionPreference = 'Continue'
# Normalize bool-like string flags passed from cmd.exe (avoid [bool] CLI parse failures)
$CreateNamespaceFlag = @('1','true','yes','on') -contains ([string]$CreateNamespace).Trim().ToLowerInvariant()
$EnableHpaFlag = @('1','true','yes','on') -contains ([string]$EnableHpa).Trim().ToLowerInvariant()
Set-Location (Split-Path $PSScriptRoot -Parent)
if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) { Write-Host 'Error: kubectl is not installed or not on PATH.'; exit 1 }
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { Write-Host 'Error: Docker CLI is not installed or not on PATH.'; exit 1 }
if ($Kubeconfig) { $Kubeconfig = [Environment]::ExpandEnvironmentVariables($Kubeconfig); if (-not (Test-Path -LiteralPath $Kubeconfig)) { Write-Host ('Error: kubeconfig file not found: ' + $Kubeconfig); exit 1 } }
$script:KubeBase = @()
if ($Kubeconfig) { $script:KubeBase += @('--kubeconfig', $Kubeconfig) }
if ($Context) { $script:KubeBase += @('--context', $Context) }
function Kube {
  if ($script:KubeBase -and $script:KubeBase.Count -gt 0) { & kubectl @script:KubeBase @args } else { & kubectl @args }
}
$script:DeploymentMutated = $False
function Fail([string]$Message) {
  Write-Host ''; Write-Host '===== KUBERNETES DEPLOYMENT FAILED ====='
  Write-Host ('Error: ' + $Message)
  Write-Host ('Mode: ' + $Mode + ' Context: ' + $Context + ' Namespace: ' + $Namespace)
  Write-Host 'Pods:'; Kube get pods -n $(if ($Namespace) { $Namespace } else { 'default' }) -l ('app=' + $Name) --output=wide 2>&1
  Write-Host 'Deployment details:'; Kube describe ('deployment/' + $Name) -n $(if ($Namespace) { $Namespace } else { 'default' }) 2>&1
  Write-Host 'Recent events:'; Kube get events -n $(if ($Namespace) { $Namespace } else { 'default' }) --sort-by=.lastTimestamp 2>&1 | Select-Object -Last 20
  Write-Host 'Container logs:'; Kube logs ('deployment/' + $Name) -n $(if ($Namespace) { $Namespace } else { 'default' }) --all-containers=true --tail=120 2>&1
  if ($Mode -eq 'production' -and $script:DeploymentMutated) { Write-Host 'Automatic rollback:' -ForegroundColor Yellow; Kube rollout undo ('deployment/' + $Name) -n $Namespace 2>&1; if ($LASTEXITCODE -eq 0) { Kube rollout status ('deployment/' + $Name) -n $Namespace --timeout=5m 2>&1 } else { Write-Host 'No previous rollout revision was available.' } }
  Write-Host ('Describe: kubectl ' + ($script:KubeBase -join ' ') + ' describe deployment/' + $Name + ' -n ' + $Namespace)
  exit 1
}
if ($Mode -eq 'production' -and -not $Context) { Fail 'Production Kubernetes requires an explicit context. Global current-context is never used implicitly.' }
[string]$ResolvedContext = $(if ($Mode -eq 'production') { $Context } else { Kube config current-context 2>$null })
$ResolvedContext = $ResolvedContext.Trim()
if (-not $ResolvedContext) { Fail 'No usable Kubernetes context was resolved.' }
if ($Mode -eq 'production' -and $ResolvedContext -eq 'docker-desktop') { Fail 'Production Kubernetes cannot target docker-desktop. Select a managed cluster context.' }
if ($Mode -eq 'local' -and -not $Context) { $Context = $ResolvedContext }
Kube cluster-info 2>&1 | Out-Host
if ($LASTEXITCODE -ne 0) { Fail ('Cannot reach Kubernetes context ' + $ResolvedContext + '.') }
if (-not $Namespace) { $Namespace = [string](Kube config view --minify --output 'jsonpath={..namespace}' 2>$null); $Namespace = $Namespace.Trim() }
if (-not $Namespace) { $Namespace = 'default' }
if ($CreateNamespaceFlag) { Kube apply -f 'k8s/namespace.yaml'; if ($LASTEXITCODE -ne 0) { Fail ('Could not create or update namespace ' + $Namespace + '.') } }
Kube get namespace $Namespace 1>$null 2>$null
if ($LASTEXITCODE -ne 0) { Fail ('Namespace ' + $Namespace + ' does not exist. Create it or select an existing namespace.') }
Write-Host ('Mode=' + $Mode + ' context=' + $ResolvedContext + ' namespace=' + $Namespace + ' image=' + $Image)
if ($Mode -eq 'local') { Write-Host 'TARGET TYPE: LOCAL DEVELOPMENT. localhost/port-forward is expected.' -ForegroundColor Yellow } else { Write-Host 'TARGET TYPE: PRODUCTION/REMOTE. No localhost fallback will be used.' -ForegroundColor Green }
$canDeploy = [string](Kube auth can-i create deployments.apps -n $Namespace 2>$null)
$canService = [string](Kube auth can-i create services -n $Namespace 2>$null)
$canSecret = [string](Kube auth can-i create secrets -n $Namespace 2>$null)
$canPatchSecret = [string](Kube auth can-i patch secrets -n $Namespace 2>$null)
if ($canDeploy.Trim() -ne 'yes' -or $canService.Trim() -ne 'yes') { Fail 'RBAC needs create/update Deployment and Service permissions.' }
if ($env:ANYCLOUD_SECRET_NAMES -and ($canSecret.Trim() -ne 'yes' -or $canPatchSecret.Trim() -ne 'yes')) { Fail 'RBAC needs create and patch Secret permissions for runtime API keys.' }
if ($Exposure -eq 'ingress') { $canIngress = [string](Kube auth can-i create ingresses.networking.k8s.io -n $Namespace 2>$null); $canPatchIngress = [string](Kube auth can-i patch ingresses.networking.k8s.io -n $Namespace 2>$null); if ($canIngress.Trim() -ne 'yes' -or $canPatchIngress.Trim() -ne 'yes') { Fail 'RBAC needs create and patch Ingress permissions.' } }
if ($ImagePullSecret -and -not $env:REGISTRY_TOKEN) { Kube get secret $ImagePullSecret -n $Namespace 1>$null 2>$null; if ($LASTEXITCODE -ne 0) { Fail ('Image pull secret not found and no session registry token was supplied: ' + $ImagePullSecret) } }
if ($TlsSecret) { Kube get secret $TlsSecret -n $Namespace 1>$null 2>$null; if ($LASTEXITCODE -ne 0) { Fail ('Ingress TLS secret not found: ' + $TlsSecret) } }
if (-not (Test-Path '.\Dockerfile')) { Fail 'Dockerfile missing. Analyze Project, then Save.' }
if (-not (Test-Path '.\k8s\deployment.yaml') -or -not (Test-Path '.\k8s\service.yaml')) { Fail 'Kubernetes manifests missing. Analyze Project, then Save.' }
$ManifestArgs = @('-f', 'k8s/service.yaml')
if (Test-Path '.\k8s\configmap.yaml') { $ManifestArgs += @('-f', 'k8s/configmap.yaml') }
if ($EnableHpaFlag) { if (-not (Test-Path '.\k8s\hpa.yaml')) { Fail 'Autoscaling is enabled but k8s/hpa.yaml is missing. Analyze and Save again.' }; $ManifestArgs += @('-f', 'k8s/hpa.yaml') }
if ($Exposure -eq 'ingress') { if (-not (Test-Path '.\k8s\ingress.yaml')) { Fail 'Ingress exposure selected but k8s/ingress.yaml is missing. Analyze and Save again.' }; $ManifestArgs += @('-f', 'k8s/ingress.yaml') }
if ($Mode -eq 'production') {
  if (-not $Repository) { Fail 'Image repository is required.' }
  switch ($RegistryType) {
    'dockerhub' { if (-not $RegistryUsername -and $Repository -notmatch '/') { Fail 'Docker Hub username is required when repository is not namespace/name.' }; if ($env:REGISTRY_TOKEN) { $env:REGISTRY_TOKEN | docker login -u $RegistryUsername --password-stdin; if ($LASTEXITCODE -ne 0) { Fail 'Docker Hub login failed. Re-enter the token.' } }; $Image = $(if ($Repository -match '/') { $Repository } else { $RegistryUsername + '/' + $Repository }) + ':' + $ImageTag }
    'ecr' { if (-not (Get-Command aws -ErrorAction SilentlyContinue)) { Fail 'AWS CLI is required for Amazon ECR.' }; if (-not $RegistryRegion) { Fail 'Amazon ECR region is required.' }; $AwsBase=@(); if ($RegistryProfile) { $AwsBase += @('--profile',$RegistryProfile) }; $Account=[string](& aws @AwsBase sts get-caller-identity --query Account --output text); if ($LASTEXITCODE -ne 0 -or $Account -notmatch '^\d{12}$') { Fail 'AWS account verification failed. Sign in to the intended AWS profile.' }; & aws @AwsBase ecr describe-repositories --region $RegistryRegion --repository-names $Repository 1>$null 2>$null; if ($LASTEXITCODE -ne 0) { Write-Host ('Creating missing ECR repository ' + $Repository); & aws @AwsBase ecr create-repository --region $RegistryRegion --repository-name $Repository 1>$null; if ($LASTEXITCODE -ne 0) { Fail 'ECR repository is missing and could not be created.' } }; $RegistryUrl=$Account+'.dkr.ecr.'+$RegistryRegion+'.amazonaws.com'; $Password=[string](& aws @AwsBase ecr get-login-password --region $RegistryRegion); if ($LASTEXITCODE -ne 0) { Fail 'Could not obtain ECR login password.' }; $Password | docker login --username AWS --password-stdin $RegistryUrl; if ($LASTEXITCODE -ne 0) { Fail 'Docker login to Amazon ECR failed.' }; $Image=$RegistryUrl+'/'+$Repository+':'+$ImageTag }
    'acr' { if (-not (Get-Command az -ErrorAction SilentlyContinue)) { Fail 'Azure CLI is required for Azure Container Registry.' }; if (-not $RegistryName) { Fail 'Azure registry name is required.' }; az account show 1>$null 2>$null; if ($LASTEXITCODE -ne 0) { Fail 'Azure CLI is not signed in. Run az login.' }; az acr show --name $RegistryName 1>$null 2>$null; if ($LASTEXITCODE -ne 0) { Fail 'The selected Azure Container Registry was not found in the active subscription.' }; az acr login --name $RegistryName; if ($LASTEXITCODE -ne 0) { Fail 'Azure Container Registry login failed.' }; $RegistryUrl=$RegistryName+'.azurecr.io'; $Image=$RegistryUrl+'/'+$Repository+':'+$ImageTag }
    'gar' { if (-not (Get-Command gcloud -ErrorAction SilentlyContinue)) { Fail 'Google Cloud CLI is required for Artifact Registry.' }; if (-not $RegistryProject -or -not $RegistryRegion -or -not $ArtifactRepository) { Fail 'Google project, location and Artifact Registry repository are required.' }; $Active=[string](gcloud auth list --filter=status:ACTIVE --format='value(account)'); if (-not $Active.Trim()) { Fail 'Google Cloud CLI has no active account. Run gcloud auth login.' }; gcloud artifacts repositories describe $ArtifactRepository --location $RegistryRegion --project $RegistryProject 1>$null 2>$null; if ($LASTEXITCODE -ne 0) { Write-Host ('Creating missing Artifact Registry repository ' + $ArtifactRepository); gcloud artifacts repositories create $ArtifactRepository --repository-format=docker --location=$RegistryRegion --project=$RegistryProject --quiet; if ($LASTEXITCODE -ne 0) { Fail 'Artifact Registry repository is missing and could not be created.' } }; $RegistryUrl=$RegistryRegion+'-docker.pkg.dev'; gcloud auth configure-docker $RegistryUrl --quiet; if ($LASTEXITCODE -ne 0) { Fail 'Docker authentication for Google Artifact Registry failed.' }; $Image=$RegistryUrl+'/'+$RegistryProject+'/'+$ArtifactRepository+'/'+$Repository+':'+$ImageTag }
    'ghcr' { if (-not $RegistryUsername -or -not $env:REGISTRY_TOKEN) { Fail 'GitHub username and a session-only token with package write permission are required.' }; $env:REGISTRY_TOKEN | docker login ghcr.io -u $RegistryUsername --password-stdin; if ($LASTEXITCODE -ne 0) { Fail 'GitHub Container Registry login failed.' }; $Image='ghcr.io/'+$RegistryUsername+'/'+$Repository+':'+$ImageTag }
    default { Fail ('Unsupported registry type: ' + $RegistryType) }
  }
}
Write-Host ('Resolved image: ' + $Image)
if ($Mode -eq 'production' -and $ImagePullSecret -and $env:REGISTRY_TOKEN) {
  $SecretServer=$(if ($RegistryType -eq 'dockerhub') { 'https://index.docker.io/v1/' } elseif ($RegistryType -eq 'ghcr') { 'ghcr.io' } else { $RegistryUrl });
  $PullUser=$(if ($RegistryType -eq 'ecr') { 'AWS' } else { $RegistryUsername });
  $PullYaml = Kube create secret docker-registry $ImagePullSecret -n $Namespace --docker-server=$SecretServer --docker-username=$PullUser --docker-password=$env:REGISTRY_TOKEN --dry-run=client -o yaml;
  if ($LASTEXITCODE -ne 0) { Fail 'Could not generate the image pull Secret.' }; $PullYaml | & kubectl @script:KubeBase apply -f -; if ($LASTEXITCODE -ne 0) { Fail 'Could not create/update the image pull Secret.' }; Write-Host ('Created/updated image pull Secret ' + $ImagePullSecret + ' without writing credentials to disk.')
}
Write-Host '[0/7] Apply session-only API keys as a Kubernetes Secret'
$SecretName = $Name + '-api-keys'
$SecretKeys = @($env:ANYCLOUD_SECRET_NAMES -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^[A-Z][A-Z0-9_]*$' })
$SecretArgs = @('create', 'secret', 'generic', $SecretName, '-n', $Namespace, '--dry-run=client', '-o', 'yaml')
$AppliedSecretKeys = @()
foreach ($SecretKey in $SecretKeys) { $SecretValue = [Environment]::GetEnvironmentVariable($SecretKey); if ($SecretValue) { $SecretArgs += ('--from-literal=' + $SecretKey + '=' + $SecretValue); $AppliedSecretKeys += $SecretKey } }
if ($AppliedSecretKeys.Count -gt 0) {
  $SecretYaml = & kubectl @script:KubeBase @SecretArgs
  if ($LASTEXITCODE -ne 0) { Fail 'Could not generate the Kubernetes Secret manifest.' }
  $SecretYaml | & kubectl @script:KubeBase apply -f -
  if ($LASTEXITCODE -ne 0) { Fail 'Could not apply the Kubernetes Secret.' }
  Write-Host ('Applied ' + $AppliedSecretKeys.Count + ' API key(s) without printing/saving values: ' + ($AppliedSecretKeys -join ', '))
} else { Write-Host 'WARNING: No Runtime API keys supplied.' -ForegroundColor Yellow }
docker info 2>&1 | Out-Host
if ($LASTEXITCODE -ne 0) { Fail 'Docker engine is not running.' }
if ($Mode -eq 'production') {
  Write-Host '[1/7] Try pulling existing registry image (skip rebuild when already published)'
  docker pull $Image 2>&1 | Out-Host
  if ($LASTEXITCODE -eq 0) {
    Write-Host ('Pulled existing image ' + $Image + ' - build skipped to save time and bandwidth.') -ForegroundColor Green
  } else {
    Write-Host 'Image not found in registry (or not accessible). Building and pushing a new image...' -ForegroundColor Yellow
    Write-Host '[1b/7] Build optimized container image'
    docker build --pull --build-arg APP_PORT=$ContainerPort -t $Image .
    if ($LASTEXITCODE -ne 0) { Fail 'docker build failed.' }
    Write-Host '[2/7] Push image to configured OCI registry'
    docker push $Image
    if ($LASTEXITCODE -ne 0) { Fail ('docker push failed for ' + $Image + '. Verify registry login and repository permission.') }
  }
} else {
  Write-Host '[1/7] Build container image (local mode)'
  docker build --pull --build-arg APP_PORT=$ContainerPort -t $Image .
  if ($LASTEXITCODE -ne 0) { Fail 'docker build failed.' }
  Write-Host '[2/7] Local image ready (push skipped for local mode)'
}
# Registry reachability: prefer docker image inspect (local after pull) over manifest inspect (often fails on Docker Desktop)
docker image inspect $Image 1>$null 2>$null
if ($LASTEXITCODE -ne 0) {
  docker manifest inspect $Image 1>$null 2>$null
  if ($LASTEXITCODE -ne 0) { Fail ('Image not readable locally or in registry: ' + $Image) }
}
Write-Host '[3/7] Validate manifests against the selected cluster'
if (-not (Test-Path -LiteralPath 'k8s/deployment.yaml')) { Fail 'k8s/deployment.yaml is missing. Analyze Project, then Save.' }
# Reliable image injection: rewrite image: lines in the Deployment YAML (avoids kubectl set image --local failures on Windows)
$DeployYaml = Get-Content -LiteralPath 'k8s/deployment.yaml' -Raw
if ([string]::IsNullOrWhiteSpace($DeployYaml)) { Fail 'k8s/deployment.yaml is empty.' }
if ($DeployYaml -notmatch '(?m)^s*image:s*') { Fail 'k8s/deployment.yaml has no image: field to update.' }
$RenderedDeployment = [regex]::Replace($DeployYaml, '(?m)^(s*image:s*)S+', ('$1' + $Image))
if ($RenderedDeployment -notmatch [regex]::Escape($Image)) { Fail ('Failed to inject image ' + $Image + ' into Deployment YAML.') }
$tmpDeploy = Join-Path $env:TEMP ('anycloud-deploy-' + $Name + '.yaml')
Set-Content -LiteralPath $tmpDeploy -Value $RenderedDeployment -Encoding utf8
Write-Host ('Using image ' + $Image + ' in Deployment')
$dry = & kubectl @script:KubeBase apply --dry-run=server -n $Namespace -f $tmpDeploy 2>&1
Write-Host $dry
if ($LASTEXITCODE -ne 0) { Fail ('Server-side Deployment validation failed: ' + $dry) }
Kube apply --dry-run=server -n $Namespace @ManifestArgs 2>&1 | Out-Host
if ($LASTEXITCODE -ne 0) { Fail 'Server-side validation of Service/ConfigMap/HPA manifests failed.' }
Write-Host '[4/7] Create or update Kubernetes resources'
Kube apply -n $Namespace @ManifestArgs 2>&1 | Out-Host
if ($LASTEXITCODE -ne 0) { Fail 'kubectl apply of Service/ConfigMap/HPA failed.' }
& kubectl @script:KubeBase apply -n $Namespace -f $tmpDeploy 2>&1 | Out-Host
if ($LASTEXITCODE -ne 0) { Fail 'Could not create/update the Deployment.' }
Remove-Item -LiteralPath $tmpDeploy -Force -ErrorAction SilentlyContinue
$script:DeploymentMutated = $True
if ($Mode -eq 'production' -and $Exposure -eq 'loadbalancer') { Kube delete ingress $Name -n $Namespace --ignore-not-found 1>$null 2>$null }
Kube rollout restart ('deployment/' + $Name) -n $Namespace
if ($LASTEXITCODE -ne 0) { Fail 'Could not start the rolling update.' }
Write-Host '[5/7] Wait until Deployment and Pods are healthy'
Kube rollout status ('deployment/' + $Name) -n $Namespace --timeout=8m
if ($LASTEXITCODE -ne 0) { Fail 'Deployment rollout did not become ready within 8 minutes.' }
Kube wait --for=condition=available ('deployment/' + $Name) -n $Namespace --timeout=60s
if ($LASTEXITCODE -ne 0) { Fail 'Deployment is not Available after rollout.' }
Kube get deployment $Name -n $Namespace --output=wide
Kube get pods -n $Namespace -l ('app=' + $Name) --output=wide
Kube get service $Name -n $Namespace --output=wide
if ($LASTEXITCODE -ne 0) { Fail 'Service was not created.' }
Write-Host '[6/7] Resolve application endpoint'
$Endpoint = $null
$EndpointKind = $(if ($Exposure -eq 'ingress') { 'Ingress' } else { 'LoadBalancer' })
$MaxEndpointAttempts = $(if ($Mode -eq 'production') { 30 } else { 18 })
for ($attempt = 1; $attempt -le $MaxEndpointAttempts; $attempt++) {
  if ($Exposure -eq 'ingress') {
    $Endpoint = [string](Kube get ingress $Name -n $Namespace -o 'jsonpath={.status.loadBalancer.ingress[0].hostname}' 2>$null)
    if (-not $Endpoint) { $Endpoint = [string](Kube get ingress $Name -n $Namespace -o 'jsonpath={.status.loadBalancer.ingress[0].ip}' 2>$null) }
  } else {
    $Endpoint = [string](Kube get service $Name -n $Namespace -o 'jsonpath={.status.loadBalancer.ingress[0].hostname}' 2>$null)
    if (-not $Endpoint) { $Endpoint = [string](Kube get service $Name -n $Namespace -o 'jsonpath={.status.loadBalancer.ingress[0].ip}' 2>$null) }
  }
  $Endpoint = $Endpoint.Trim()
  if ($Endpoint) { break }
  Write-Host ('    ' + $EndpointKind + ' endpoint pending (' + $attempt + '/' + $MaxEndpointAttempts + ')...')
  Start-Sleep -Seconds 10
}
if (-not $Endpoint -and $Mode -eq 'production') { Fail ($EndpointKind + ' did not receive a public address. Verify the cloud load-balancer/ingress controller and events.') }
if ($Endpoint) {
  $UrlHost = $(if ($Exposure -eq 'ingress' -and $IngressHost) { $IngressHost } else { $Endpoint })
  $Scheme = $(if ($Exposure -eq 'ingress' -and $TlsSecret) { 'https' } else { 'http' })
  $Url = $Scheme + '://' + $UrlHost + '/'
  $HealthUrl = $Scheme + '://' + $UrlHost + $HealthPath
  Write-Host '[7/7] Verify public HTTP health'
  $Reachable = $False
  for ($probe = 1; $probe -le 8; $probe++) { try { $r = Invoke-WebRequest -UseBasicParsing -Uri $HealthUrl -TimeoutSec 12; if ([int]$r.StatusCode -ge 200 -and [int]$r.StatusCode -lt 500) { $Reachable = $True; break } } catch {}; if ($probe -lt 8) { Start-Sleep -Seconds 10 } }
  if ($Mode -eq 'production' -and -not $Reachable) { Fail ('Public endpoint was assigned but HTTP health did not pass: ' + $HealthUrl) }
  Write-Host ''; Write-Host '============================================================'
  Write-Host ('ANYCLOUD KUBERNETES URL: ' + $Url)
  Write-Host ('ENDPOINT CHECK: ' + $(if ($Reachable) { 'REACHABLE' } else { 'NOT REACHABLE YET' }))
  Write-Host '============================================================'; Write-Host ''
} else {
  Write-Host 'No external endpoint on local cluster. Starting localhost port-forward fallback...'
  $LocalPort = $ContainerPort
  while ($LocalPort -lt ($ContainerPort + 100)) { $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $LocalPort); try { $listener.Start(); $listener.Stop(); break } catch { $LocalPort++ } }
  if ($LocalPort -ge ($ContainerPort + 100)) { Fail 'No free local port found for kubectl port-forward.' }
  $ForwardArgs = @($script:KubeBase + @('-n', $Namespace, 'port-forward', ('service/' + $Name), ($LocalPort.ToString() + ':80'), '--address', '127.0.0.1'))
  $Forward = Start-Process -FilePath 'kubectl' -ArgumentList $ForwardArgs -WindowStyle Hidden -PassThru
  Start-Sleep -Seconds 3
  if ($Forward.HasExited) { Fail 'kubectl port-forward could not start.' }
  $Url = 'http://127.0.0.1:' + $LocalPort + '/'
  Write-Host ''; Write-Host '============================================================'
  Write-Host ('ANYCLOUD KUBERNETES URL: ' + $Url)
  Write-Host ('LOCAL PORT-FORWARD PID: ' + $Forward.Id)
  Write-Host 'This localhost URL works while the background port-forward process is running.'
  Write-Host '============================================================'; Write-Host ''
}
Write-Host ('Kubernetes ' + $Mode + ' deployment finished.')
