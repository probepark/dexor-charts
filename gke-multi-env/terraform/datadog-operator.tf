# ==============================================================================
# DATADOG OPERATOR CONFIGURATION
# ==============================================================================
# This file manages the Datadog Operator deployment for monitoring and observability
# The operator manages Datadog Agent deployments through the DatadogAgent CRD

# Variables are defined in main.tf:
# - var.enable_datadog: Enable/disable Datadog monitoring
# - var.datadog_api_key: Datadog API key (sensitive)
# - var.datadog_app_key: Datadog Application key (sensitive)
# - var.datadog_site: Datadog site (e.g., datadoghq.com, datadoghq.eu)

# ==============================================================================
# EXAMPLE USAGE
# ==============================================================================
# To enable Datadog monitoring, set these variables in your terraform.tfvars:
#
# enable_datadog   = true
# datadog_api_key  = "your-datadog-api-key"
# datadog_app_key  = "your-datadog-app-key"
# datadog_site     = "datadoghq.com"  # or "datadoghq.eu" for EU region
#
# After deployment, you can verify the installation:
# kubectl get pods -n datadog
# kubectl get datadogagent -n datadog
#
# To create custom monitors or dashboards, you can use DatadogMonitor CRDs:
# kubectl apply -f your-datadog-monitor.yaml

# ==============================================================================
# DATADOG FEATURES ENABLED
# ==============================================================================
# The following Datadog features are enabled by default:
# - APM (Application Performance Monitoring) with trace collection
# - Log Collection from all containers
# - Live Process Monitoring
# - Live Container Monitoring
# - Network Performance Monitoring (NPM)
# - Orchestrator Explorer for Kubernetes visibility
# - Prometheus metrics scraping
# - Universal Service Monitoring (USM)
#
# Resource allocations are optimized for each environment:
# - Dev: Minimal resources for cost efficiency
# - Prod: Higher resources and replicas for reliability

# ==============================================================================
# CUSTOM CONFIGURATION
# ==============================================================================
# To add custom Datadog configuration:
# 1. Modify the DatadogAgent manifest in main.tf
# 2. Add environment-specific overrides in the override section
# 3. Use ConfigMaps for custom agent configurations
#
# For application-specific monitoring:
# 1. Add Datadog annotations to your pods/services
# 2. Use autodiscovery templates for custom integrations
# 3. Configure APM tracing in your applications

# ==============================================================================
# TROUBLESHOOTING
# ==============================================================================
# Common issues and solutions:
#
# 1. Agent pods not starting:
#    - Check API/App key secrets: kubectl get secret datadog-secret -n datadog -o yaml
#    - Verify node resources are sufficient
#    - Check pod events: kubectl describe pod <pod-name> -n datadog
#
# 2. Metrics not appearing in Datadog:
#    - Verify cluster name matches in Datadog UI
#    - Check agent logs: kubectl logs <agent-pod> -n datadog
#    - Ensure firewall rules allow outbound HTTPS to Datadog
#
# 3. APM traces not collected:
#    - Verify hostPort 8126 is accessible
#    - Check application is sending traces to correct endpoint
#    - Review APM agent configuration in your application

# ==============================================================================
# MONITORING BEST PRACTICES
# ==============================================================================
# 1. Use tags consistently across all resources:
#    - environment: dev/qa/prod
#    - service: your-service-name
#    - version: deployment version
#
# 2. Set up alerts for critical metrics:
#    - High CPU/Memory usage
#    - Pod restarts
#    - Error rates
#    - Custom business metrics
#
# 3. Create dashboards for:
#    - Service overview
#    - Infrastructure health
#    - Application performance
#    - Business metrics
#
# 4. Enable log aggregation with proper parsing:
#    - Use structured logging (JSON)
#    - Include correlation IDs
#    - Set appropriate log levels

# ==============================================================================
# COST OPTIMIZATION
# ==============================================================================
# To optimize Datadog costs:
# 1. Use log sampling for high-volume services
# 2. Set appropriate metric retention policies
# 3. Disable unused features in non-production environments
# 4. Use custom metrics judiciously
# 5. Configure APM sampling rates based on traffic volume

# ==============================================================================
# SECURITY CONSIDERATIONS
# ==============================================================================
# 1. API and App keys are stored as Kubernetes secrets
# 2. Use RBAC to limit access to Datadog namespace
# 3. Enable audit logging for configuration changes
# 4. Regularly rotate API keys
# 5. Use separate Datadog organizations for different environments if needed