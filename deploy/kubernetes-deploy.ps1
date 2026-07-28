# AnyCloud Studio - Kubernetes deployment with endpoint discovery
param(
  [string]$Name = 'smart-llm-gateway',
  [string]$Image = 'piyushdocker90/smart-llm-gateway:latest',
  [int]$ContainerPort = 8501
)
$ErrorActionPreference = 'Continue'
Set-Location (Split-Path $PSScriptRoot -Parent)
function Fail([string]$Message) {
  Write-Host ''; Write-Host '===== KUBERNETES DEPLOYMENT FAILED ====='
  Write-Host ('Error: ' + $Message)
  Write-Host ('Context: ' + (kubectl config current-context 2>$null))
  Write-Host 'Pods:'; kubectl get pods -l ('app=' + $Name) -o wide 2>&1
  Write-Host 'Recent events:'; kubectl get events --sort-by=.lastTimestamp 2>&1 | Select-Object -Last 20
  Write-Host ('Describe deployment: kubectl describe deployment/' + $Name)
  exit 1
}
if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) { Fail 'kubectl is not installed or not on PATH.' }
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { Fail 'Docker CLI is not installed or not on PATH.' }
$Context = (kubectl config current-context 2>$null).Trim()
if (-not $Context) { Fail 'No Kubernetes context is selected. Configure a cluster, then run kubectl config use-context CONTEXT.' }
kubectl cluster-info 2>&1 | Out-Host
if ($LASTEXITCODE -ne 0) { Fail ('Cannot reach Kubernetes context ' + $Context + '.') }
$Namespace = (kubectl config view --minify --output 'jsonpath={..namespace}' 2>$null).Trim()
if (-not $Namespace) { $Namespace = 'default' }
Write-Host ('Kubernetes context=' + $Context + ' namespace=' + $Namespace)
$canDeploy = (kubectl auth can-i create deployments.apps -n $Namespace 2>$null).Trim()
$canService = (kubectl auth can-i create services -n $Namespace 2>$null).Trim()
if ($canDeploy -ne 'yes' -or $canService -ne 'yes') { Fail ('RBAC denied in namespace ' + $Namespace + '. Need create/update deployments and services.') }
if (-not (Test-Path '.\Dockerfile')) { Fail 'Dockerfile missing. Analyze Project, then Save.' }
if (-not (Test-Path '.\k8s\deployment.yaml') -or -not (Test-Path '.\k8s\service.yaml')) { Fail 'Kubernetes manifests missing. Analyze Project, then Save.' }
Write-Host '[1/6] Build container image'
docker info 2>&1 | Out-Host
if ($LASTEXITCODE -ne 0) { Fail 'Docker Desktop/engine is not running.' }
docker build --build-arg APP_PORT=$ContainerPort -t $Image .
if ($LASTEXITCODE -ne 0) { Fail 'docker build failed.' }
Write-Host '[2/6] Push public Docker Hub image'
docker push $Image
if ($LASTEXITCODE -ne 0) { Fail 'docker push failed. Run docker login and ensure the repository can be pushed.' }
Write-Host '[3/6] Validate manifests against the selected cluster'
kubectl apply --dry-run=server -n $Namespace -f k8s
if ($LASTEXITCODE -ne 0) { Fail 'Server-side manifest validation failed.' }
Write-Host '[4/6] Apply Deployment and LoadBalancer Service'
kubectl apply -n $Namespace -f k8s
if ($LASTEXITCODE -ne 0) { Fail 'kubectl apply failed.' }
kubectl set image ('deployment/' + $Name) ($Name + '=' + $Image) -n $Namespace
if ($LASTEXITCODE -ne 0) { Fail 'Could not set the deployment image.' }
Write-Host '[5/6] Wait for rollout'
kubectl rollout status ('deployment/' + $Name) -n $Namespace --timeout=5m
if ($LASTEXITCODE -ne 0) { Fail 'Deployment rollout did not complete within 5 minutes.' }
kubectl get deployment $Name -n $Namespace -o wide
kubectl get pods -n $Namespace -l ('app=' + $Name) -o wide
kubectl get service $Name -n $Namespace -o wide
Write-Host '[6/6] Resolve public endpoint'
$Endpoint = $null
for ($attempt = 1; $attempt -le 18; $attempt++) {
  $Endpoint = (kubectl get service $Name -n $Namespace -o 'jsonpath={.status.loadBalancer.ingress[0].hostname}' 2>$null).Trim()
  if (-not $Endpoint) { $Endpoint = (kubectl get service $Name -n $Namespace -o 'jsonpath={.status.loadBalancer.ingress[0].ip}' 2>$null).Trim() }
  if ($Endpoint) { break }
  Write-Host ('    LoadBalancer endpoint pending (' + $attempt + '/18)...')
  Start-Sleep -Seconds 10
}
if ($Endpoint) {
  $Url = 'http://' + $Endpoint + '/'
  $Reachable = $false
  for ($probe = 1; $probe -le 6; $probe++) { try { $r = Invoke-WebRequest -UseBasicParsing -Uri $Url -TimeoutSec 10; if ([int]$r.StatusCode -ge 200 -and [int]$r.StatusCode -lt 500) { $Reachable = $true; break } } catch {}; if ($probe -lt 6) { Start-Sleep -Seconds 10 } }
  Write-Host ''; Write-Host '============================================================'
  Write-Host ('ANYCLOUD KUBERNETES URL: ' + $Url)
  Write-Host ('ENDPOINT CHECK: ' + $(if ($Reachable) { 'REACHABLE' } else { 'NOT REACHABLE YET - load balancer/DNS may still be provisioning' }))
  Write-Host '============================================================'; Write-Host ''
} else {
  Write-Host 'No external LoadBalancer address was assigned. Starting a local port-forward fallback...'
  $LocalPort = $ContainerPort
  while ($LocalPort -lt ($ContainerPort + 100)) {
    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $LocalPort)
    try { $listener.Start(); $listener.Stop(); break } catch { $LocalPort++ }
  }
  if ($LocalPort -ge ($ContainerPort + 100)) { Fail 'No free local port found for kubectl port-forward.' }
  $forwardArgs = @('-n', $Namespace, 'port-forward', ('service/' + $Name), ($LocalPort.ToString() + ':80'), '--address', '127.0.0.1')
  $forward = Start-Process -FilePath 'kubectl' -ArgumentList $forwardArgs -WindowStyle Hidden -PassThru
  Start-Sleep -Seconds 3
  if ($forward.HasExited) { Fail 'kubectl port-forward could not start. Check pods and RBAC pods/portforward permission.' }
  $Url = 'http://127.0.0.1:' + $LocalPort + '/'
  Write-Host ''; Write-Host '============================================================'
  Write-Host ('ANYCLOUD KUBERNETES URL: ' + $Url)
  Write-Host ('LOCAL PORT-FORWARD PID: ' + $forward.Id)
  Write-Host 'This localhost URL works while the background port-forward process is running.'
  Write-Host '============================================================'; Write-Host ''
}
Write-Host 'Kubernetes deployment finished.'
