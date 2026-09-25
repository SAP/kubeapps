// Copyright 2026 the Kubeapps contributors.
// SPDX-License-Identifier: Apache-2.0

// Package safelog contains logging helpers which deliberately avoid logging
// request payloads and metadata.
package safelog

import (
	"github.com/bufbuild/connect-go"
	log "k8s.io/klog/v2"
)

// Request logs non-sensitive RPC metadata for a Connect request.
//
// A Connect request's string representation includes its message and HTTP
// headers. Both may contain credentials, such as package values,
// Authorization, cookies or forwarded access tokens, so neither is logged.
func Request[T any](operation string, request *connect.Request[T]) {
	if request == nil {
		log.InfoS(operation)
		return
	}

	log.InfoS(operation,
		"rpc", request.Spec().Procedure,
		"httpMethod", request.HTTPMethod(),
	)
}
