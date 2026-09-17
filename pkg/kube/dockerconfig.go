// Copyright 2023 the Kubeapps contributors.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package kube

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"strings"
)

// Including here instead of importing from k8s.io/kubernetes/credentialprovider
// since k8s.io/kubernetes is not supported for imports and leads to version issues.

// the following pieces of code have been extracted from
// https://github.com/kubernetes/kubernetes/blob/916c3466b96d879687bd1426af4a9e8664eb18ef/pkg/credentialprovider/provider.go#L28
// and they are subject to the undermentioned license terms.

/*
Copyright 2014 The Kubernetes Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

// DockerConfigProvider is the interface that registered extensions implement
// to materialize 'dockercfg' credentials.
type DockerConfigProvider interface {
	// Enabled returns true if the config provider is enabled.
	// Implementations can be blocking - e.g. metadata server unavailable.
	Enabled() bool
	// Provide returns docker configuration.
	// Implementations can be blocking - e.g. metadata server unavailable.
	// The image is passed in as context in the event that the
	// implementation depends on information in the image name to return
	// credentials; implementations are safe to ignore the image.
	Provide(image string) DockerConfig
}

// DockerConfigJSON represents ~/.docker/config.json file info
// see https://github.com/docker/docker/pull/12009
type DockerConfigJSON struct {
	Auths DockerConfig `json:"auths"`
	// +optional
	HTTPHeaders map[string]string `json:"HttpHeaders,omitempty"`
}

// DockerConfig represents the config file used by the docker CLI.
// This config that represents the credentials that should be used
// when pulling images from specific image repositories.
type DockerConfig map[string]DockerConfigEntry

// DockerConfigEntry wraps a docker config as a entry
type DockerConfigEntry struct {
	Username string
	Password string
	Email    string
	Provider DockerConfigProvider
}

// dockerConfigEntryWithAuth is used solely for deserializing the Auth field
// into a dockerConfigEntry during JSON deserialization.
type dockerConfigEntryWithAuth struct {
	// +optional
	Username string `json:"username,omitempty"`
	// +optional
	Password string `json:"password,omitempty"`
	// +optional
	Email string `json:"email,omitempty"`
	// +optional
	Auth string `json:"auth,omitempty"`
}

func (ident *DockerConfigEntry) UnmarshalJSON(data []byte) error {
	var tmp dockerConfigEntryWithAuth
	err := json.Unmarshal(data, &tmp)
	if err != nil {
		return err
	}

	ident.Username = tmp.Username
	ident.Password = tmp.Password
	ident.Email = tmp.Email

	if len(tmp.Auth) == 0 {
		return nil
	}

	ident.Username, ident.Password, err = decodeDockerConfigFieldAuth(tmp.Auth)
	return err
}

func (ident DockerConfigEntry) MarshalJSON() ([]byte, error) {
	toEncode := dockerConfigEntryWithAuth{ident.Username, ident.Password, ident.Email, ""}
	toEncode.Auth = encodeDockerConfigFieldAuth(ident.Username, ident.Password)

	return json.Marshal(toEncode)
}

// decodeDockerConfigFieldAuth deserializes the "auth" field from dockercfg into a
// username and a password. The format of the auth field is base64(<username>:<password>).
func decodeDockerConfigFieldAuth(field string) (username, password string, err error) {
	decoded, err := base64.StdEncoding.DecodeString(field)
	if err != nil {
		return
	}

	parts := strings.SplitN(string(decoded), ":", 2)
	if len(parts) != 2 {
		err = fmt.Errorf("unable to parse auth field")
		return
	}

	username = parts[0]
	password = parts[1]

	return
}

func encodeDockerConfigFieldAuth(username, password string) string {
	fieldValue := username + ":" + password

	return base64.StdEncoding.EncodeToString([]byte(fieldValue))
}

// NormalizeRegistryHost normalizes a registry hostname for comparison.
// It handles common variations like docker.io vs index.docker.io.
func NormalizeRegistryHost(host string) string {
	host = strings.ToLower(strings.TrimSpace(host))
	// Docker Hub special case: docker.io and index.docker.io are equivalent
	if host == "docker.io" || host == "registry-1.docker.io" {
		return "index.docker.io"
	}
	// Remove default HTTPS port if present
	host = strings.TrimSuffix(host, ":443")
	return host
}

// GetAuthForRegistry extracts credentials for a specific registry host from a DockerConfigJSON.
// Returns the auth header (Basic base64(username:password)) if found, empty string if not found.
// The registryHost should be the hostname (and optional port) from the OCI reference.
func GetAuthForRegistry(dockerConfig *DockerConfigJSON, registryHost string) (string, error) {
	if dockerConfig == nil || len(dockerConfig.Auths) == 0 {
		return "", nil
	}

	normalizedTarget := NormalizeRegistryHost(registryHost)

	// Try exact match first
	if entry, ok := dockerConfig.Auths[normalizedTarget]; ok {
		auth := fmt.Sprintf("%s:%s", entry.Username, entry.Password)
		return fmt.Sprintf("Basic %s", base64.StdEncoding.EncodeToString([]byte(auth))), nil
	}

	// Try matching with normalization
	for configHost, entry := range dockerConfig.Auths {
		if NormalizeRegistryHost(configHost) == normalizedTarget {
			auth := fmt.Sprintf("%s:%s", entry.Username, entry.Password)
			return fmt.Sprintf("Basic %s", base64.StdEncoding.EncodeToString([]byte(auth))), nil
		}
	}

	// No match found - return empty string (no auth header)
	return "", nil
}
