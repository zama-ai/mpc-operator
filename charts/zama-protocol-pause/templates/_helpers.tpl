{{/*
Expand the name of the chart.
*/}}
{{- define "zama-protocol-pause.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "zama-protocol-pause.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "zama-protocol-pause.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
zama-protocol-pause labels
*/}}
{{- define "zama-protocol-pause.labels" -}}
helm.sh/chart: {{ include "zama-protocol-pause.chart" . }}
{{ include "zama-protocol-pause.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "zama-protocol-pause.selectorLabels" -}}
app.kubernetes.io/name: {{ include "zama-protocol-pause.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "zama-protocol-pause.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "zama-protocol-pause.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "zama-protocol-pause.namespace" -}}
{{- if .Values.namespace }}
{{- .Values.namespace }}
{{- else }}
{{- .Release.Namespace }}
{{- end }}
{{- end }}

{{/*
Fail fast when `network` is unset or not one of the supported networks.
*/}}
{{- define "zama-protocol-pause.validateNetwork" -}}
{{- $valid := list "devnet" "testnet" "mainnet" }}
{{- if not .Values.network }}
{{- fail (printf "network must be set (one of: %s)" (join ", " $valid)) }}
{{- end }}
{{- if not (has .Values.network $valid) }}
{{- fail (printf "network %q is not valid (expected one of: %s)" .Values.network (join ", " $valid)) }}
{{- end }}
{{- end }}

{{/*
Shared pause script preamble: pauser/signer derivation, the paused() status
formatter and the pause_contract function used by both cronjobs. The only
dry-run vs real difference lives here (fork+impersonate vs wallet signing), so
the actual `cast send` appears exactly once.
Args passed to pause_contract: LABEL RPC STATUS_CONTRACT SEND_TARGET [calldata...]
*/}}
{{- define "zama-protocol-pause.pauseScript" -}}
{{- $zero := "0x0000000000000000000000000000000000000000000000000000000000000000" -}}
DRY_RUN="{{ .Values.dryRun }}"
ZERO="{{ $zero }}"
{{- if and .Values.dryRun .Values.dryRunPauserImpersonationAddress }}
IMPERSONATE="true"
PAUSER_ADDRESS="{{ .Values.dryRunPauserImpersonationAddress }}"
{{- else if .Values.wallet.awsKMS.enabled }}
PAUSER_ADDRESS=$(cast wallet address --aws ${WALLET_PRIVATE_KEY})
WALLET_ARGS="--aws"
{{- else }}
PAUSER_ADDRESS=$(cast wallet address --private-key ${WALLET_PRIVATE_KEY})
WALLET_ARGS="--private-key ${WALLET_PRIVATE_KEY}"
{{- end }}
echo "Pauser address: ${PAUSER_ADDRESS}"
{{- if .Values.dryRun }}
{{- if .Values.dryRunPauserImpersonationAddress }}
echo "DRY-RUN mode: each chain is forked locally with anvil; the pauser is impersonated."
{{- else }}
echo "DRY-RUN mode: each chain is forked locally with anvil; the configured wallet signs against the fork."
{{- end }}
{{- end }}
echo "=================================================="

# Map a paused() return value to a human-readable status.
fmt_paused() {
  if [ "$1" = "${ZERO}" ]; then echo "UNPAUSED ($1)"; else echo "PAUSED ($1)"; fi
}

# Check and, if not already paused, pause a contract. In dry-run the RPC is
# forked locally with anvil; the pauser is impersonated when IMPERSONATE is set,
# otherwise the wallet signs (against the fork in dry-run, or the real RPC).
pause_contract() {
  LABEL="$1"; RPC="$2"; STATUS_CONTRACT="$3"; SEND_TARGET="$4"; shift 4
  echo "== ${LABEL} =="
  SEND_RPC="${RPC}"; SIGN_ARGS="${WALLET_ARGS}"
  if [ "${DRY_RUN}" = "true" ]; then
    anvil --fork-url "${RPC}" --port 8545 --silent &
    ANVIL_PID=$!
    SEND_RPC="http://127.0.0.1:8545"
    until cast block-number --rpc-url "${SEND_RPC}" >/dev/null 2>&1; do sleep 1; done
    if [ -n "${IMPERSONATE}" ]; then
      cast rpc anvil_impersonateAccount "${PAUSER_ADDRESS}" --rpc-url "${SEND_RPC}" >/dev/null
      SIGN_ARGS="--from ${PAUSER_ADDRESS} --unlocked"
    fi
  fi
  echo "pauser balance: $(cast balance "${PAUSER_ADDRESS}" --rpc-url "${SEND_RPC}")"
  STATUS=$(cast call "${STATUS_CONTRACT}" "paused()" --rpc-url "${SEND_RPC}")
  echo "paused() before: $(fmt_paused "${STATUS}")"
  if [ "${STATUS}" = "${ZERO}" ]; then
    echo "Pausing ${LABEL}"
    if cast send "${SEND_TARGET}" "$@" ${SIGN_ARGS} --rpc-url "${SEND_RPC}"; then
      echo "Pause transaction succeeded"
    else
      echo "FAILED to pause: ${LABEL}"
    fi
    echo "paused() after:  $(fmt_paused "$(cast call "${STATUS_CONTRACT}" "paused()" --rpc-url "${SEND_RPC}")")"
  else
    echo "Already paused, skipping"
  fi
  if [ "${DRY_RUN}" = "true" ]; then
    kill "${ANVIL_PID}" 2>/dev/null || true
    wait "${ANVIL_PID}" 2>/dev/null || true
  fi
  echo "=================================================="
}
{{- end }}