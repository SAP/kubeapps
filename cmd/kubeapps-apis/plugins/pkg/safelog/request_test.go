// Copyright 2026 the Kubeapps contributors.
// SPDX-License-Identifier: Apache-2.0

package safelog

import (
	"bytes"
	"os"
	"strings"
	"testing"

	"github.com/bufbuild/connect-go"
	log "k8s.io/klog/v2"
)

func TestRequestDoesNotLogHeadersOrMessage(t *testing.T) {
	type requestMessage struct {
		SensitiveValue string
	}

	request := connect.NewRequest(&requestMessage{SensitiveValue: "message-secret-sentinel"})
	request.Header().Set("Authorization", "header-secret-sentinel")
	request.Header().Set("Cookie", "cookie-secret-sentinel")
	request.Header().Set("X-Forwarded-Access-Token", "forwarded-token-sentinel")

	var output bytes.Buffer
	log.LogToStderr(false)
	log.SetOutput(&output)
	t.Cleanup(func() {
		log.Flush()
		log.SetOutput(os.Stderr)
		log.LogToStderr(true)
	})

	Request("test safe request log", request)
	log.Flush()

	got := output.String()
	if !strings.Contains(got, "test safe request log") {
		t.Fatalf("expected operation in log output, got %q", got)
	}
	for _, sensitiveValue := range []string{
		"message-secret-sentinel",
		"header-secret-sentinel",
		"cookie-secret-sentinel",
		"forwarded-token-sentinel",
	} {
		if strings.Contains(got, sensitiveValue) {
			t.Errorf("log output contains sensitive sentinel %q", sensitiveValue)
		}
	}
}

func TestRequestAcceptsNilRequest(t *testing.T) {
	Request[struct{}]("test nil request log", nil)
}
