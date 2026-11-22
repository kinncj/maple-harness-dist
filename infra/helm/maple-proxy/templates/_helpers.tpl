{{/* Names. */}}
{{- define "maple.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "maple.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "maple.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Labels shared by everything; selectorLabels name one component. */}}
{{- define "maple.labels" -}}
helm.sh/chart: {{ include "maple.chart" . }}
app.kubernetes.io/name: {{ include "maple.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: maple-harness
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end -}}

{{/* (dict "ctx" $ "component" "proxy") */}}
{{- define "maple.selectorLabels" -}}
app.kubernetes.io/name: {{ include "maple.name" .ctx }}
app.kubernetes.io/instance: {{ .ctx.Release.Name }}
app.kubernetes.io/component: {{ .component }}
{{- end -}}

{{/* Labels for one component's objects: the shared ones plus the component. */}}
{{- define "maple.componentLabels" -}}
{{ include "maple.labels" .ctx }}
app.kubernetes.io/component: {{ .component }}
{{- end -}}

{{- define "maple.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "maple.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/* The proxy image, by digest when one is given. Without a tag: the chart's appVersion, written
     proxy-<appVersion> for a repository named maple-harness (Docker Hub, where every Maple image
     is named by a tag prefix, or a copy of it), and as is for any other (your own build). */}}
{{- define "maple.image" -}}
{{- if .Values.image.digest -}}
{{- printf "%s@%s" .Values.image.repository .Values.image.digest -}}
{{- else if .Values.image.tag -}}
{{- printf "%s:%s" .Values.image.repository .Values.image.tag -}}
{{- else if hasSuffix "/maple-harness" .Values.image.repository -}}
{{- printf "%s:proxy-%s" .Values.image.repository .Chart.AppVersion -}}
{{- else -}}
{{- printf "%s:%s" .Values.image.repository .Chart.AppVersion -}}
{{- end -}}
{{- end -}}

{{/* The names the proxy's Service answers to, plus allowedHosts. */}}
{{- define "maple.allowedHosts" -}}
{{- $f := include "maple.fullname" . -}}
{{- $ns := .Release.Namespace -}}
{{- $hosts := list $f (printf "%s.%s" $f $ns) (printf "%s.%s.svc" $f $ns) (printf "%s.%s.svc.%s" $f $ns .Values.clusterDomain) -}}
{{- join "," (concat $hosts .Values.allowedHosts) -}}
{{- end -}}

{{/* Where the settings of a central or redis replica come from: settings.source, or the mode's own
store when it is empty (central in mode central, redis in mode redis). Empty in disk mode. */}}
{{- define "maple.settingsSource" -}}
{{- if eq .Values.mode "central" -}}
{{- default "central" .Values.settings.source -}}
{{- else if eq .Values.mode "redis" -}}
{{- default "redis" .Values.settings.source -}}
{{- end -}}
{{- end -}}

{{/* Checks that stop an install with a reason instead of a pod that cannot start. */}}
{{- define "maple.validate" -}}
{{- if not (has .Values.mode (list "disk" "central" "redis")) -}}
{{- fail (printf "mode must be disk, central or redis, not %q" .Values.mode) -}}
{{- end -}}
{{- if not .Values.existingSecret -}}
{{- fail "existingSecret is required: create a Secret with at least access.proxy_tokens (kubectl create secret generic maple-proxy --from-file=access.proxy_tokens=./proxy_tokens) and set existingSecret to its name. The chart never puts tokens or passwords in values." -}}
{{- end -}}
{{- if and (eq .Values.mode "disk") (ne (int .Values.replicaCount) 1) -}}
{{- fail "mode disk keeps everything on one volume and runs one replica: set replicaCount: 1, or mode: central (or redis) for several replicas" -}}
{{- end -}}
{{- if lt (int .Values.replicaCount) 1 -}}
{{- fail "replicaCount must be at least 1" -}}
{{- end -}}
{{- $source := include "maple.settingsSource" . -}}
{{- if and (eq .Values.mode "central") (not (has $source (list "central" "file"))) -}}
{{- fail (printf "settings.source must be central or file in mode central, not %q" .Values.settings.source) -}}
{{- end -}}
{{- if eq .Values.mode "redis" -}}
{{- if has $source (list "central" "postgres") -}}
{{- fail (printf "settings.source %q keeps the settings in PostgreSQL, and mode redis has none: leave settings.source empty (the settings are kept in Redis) or set it to file" .Values.settings.source) -}}
{{- end -}}
{{- if not (has $source (list "redis" "file")) -}}
{{- fail (printf "settings.source must be redis or file in mode redis, not %q" .Values.settings.source) -}}
{{- end -}}
{{- if .Values.postgres.enabled -}}
{{- fail "mode redis keeps everything in Redis and runs no PostgreSQL: turn postgres.enabled off, or use mode: central to keep durable data in PostgreSQL (the recommendation)" -}}
{{- end -}}
{{- range .Values.extraEnv -}}
{{- if eq (toString .name) "MAPLE_POSTGRES_DSN" -}}
{{- fail "mode redis keeps everything in Redis, but extraEnv sets MAPLE_POSTGRES_DSN (the proxy refuses it): remove it, or use mode: central" -}}
{{- end -}}
{{- end -}}
{{- if regexMatch "(?m)^\\s*postgres_dsn\\s*:" .Values.config -}}
{{- fail "mode redis keeps everything in Redis, but config sets storage.postgres_dsn (the proxy refuses it): remove it, or use mode: central" -}}
{{- end -}}
{{- if .Values.persistence.data.existingClaim -}}
{{- fail "mode redis gives each replica a data volume of its own (persistence.data size and storageClass): persistence.data.existingClaim cannot serve every replica, leave it empty" -}}
{{- end -}}
{{- end -}}
{{- if and .Values.postgres.enabled (not .Values.postgres.existingSecret) -}}
{{- fail "postgres.enabled needs postgres.existingSecret: a Secret with the database password under the key password" -}}
{{- end -}}
{{- if and .Values.redis.enabled (not .Values.redis.existingSecret) -}}
{{- fail "redis.enabled needs redis.existingSecret: a Secret with the Redis password under the key password" -}}
{{- end -}}
{{- if and .Values.postgres.enabled (ne .Values.mode "central") -}}
{{- fail "the sample PostgreSQL is for mode: central" -}}
{{- end -}}
{{- if and .Values.redis.enabled (eq .Values.mode "disk") -}}
{{- fail "the sample Redis is for mode: central (memory only) or mode: redis (durable)" -}}
{{- end -}}
{{- if and .Values.mcpHub.enabled (not .Values.mcpHub.existingSecret) -}}
{{- fail "mcpHub.enabled needs mcpHub.existingSecret: the hub's own Secret (access.mcp_hub_tokens), never the proxy's" -}}
{{- end -}}
{{- if and .Values.mcpHub.enabled (eq .Values.mcpHub.existingSecret .Values.existingSecret) -}}
{{- fail "mcpHub.existingSecret must not be the proxy's Secret: the hub runs programs and must never see the database password or the storage key" -}}
{{- end -}}
{{- if and .Values.lake.enabled (ne .Values.mode "central") -}}
{{- fail "lake.enabled moves usage from the shared PostgreSQL: it needs mode: central" -}}
{{- end -}}
{{- if and .Values.lake.enabled (not .Values.lake.existingSecret) -}}
{{- fail "lake.enabled needs lake.existingSecret: a Secret with postgres_dsn for the lake jobs' own PostgreSQL role" -}}
{{- end -}}
{{- if and .Values.metrics.serviceMonitor.enabled (not .Values.metrics.serviceMonitor.tokenSecret.name) -}}
{{- fail "metrics.serviceMonitor.enabled needs metrics.serviceMonitor.tokenSecret.name: the Secret holding the metrics-scope token Prometheus sends" -}}
{{- end -}}
{{- end -}}
