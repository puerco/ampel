// SPDX-FileCopyrightText: Copyright 2026 Carabiner Systems, Inc
// SPDX-License-Identifier: Apache-2.0

package fuzz

import (
	"bytes"
	"testing"

	ampelcontext "github.com/carabiner-dev/ampel/pkg/context"
	"github.com/carabiner-dev/ampel/pkg/evaluator/class"
)

// FuzzParseProviderJSON exercises the JSON context-provider parser. It must
// never panic: malformed input is expected to surface as an error.
func FuzzParseProviderJSON(f *testing.F) {
	f.Add([]byte(`{"a":1}`))
	f.Add([]byte(`{"nested":{"list":[1,2,3],"s":"x"}}`))
	f.Add([]byte(`{}`))
	f.Add([]byte(``))
	f.Add([]byte(`[1,2,3]`))

	f.Fuzz(func(t *testing.T, data []byte) {
		_, _ = ampelcontext.NewProviderFromJSON(bytes.NewReader(data))
	})
}

// FuzzParseProviderYAML exercises the YAML context-provider parser.
func FuzzParseProviderYAML(f *testing.F) {
	f.Add([]byte("a: 1\n"))
	f.Add([]byte("nested:\n  list:\n    - 1\n    - 2\n  s: x\n"))
	f.Add([]byte("{}"))
	f.Add([]byte(""))

	f.Fuzz(func(t *testing.T, data []byte) {
		_, _ = ampelcontext.NewProviderFromYAML(bytes.NewReader(data))
	})
}

// FuzzParseIdentity exercises the plugin/transformer identity parser
// ("name@vN"). It must never panic on arbitrary input.
func FuzzParseIdentity(f *testing.F) {
	f.Add("cel@v1")
	f.Add("semver")
	f.Add("name@v0")
	f.Add("@v1")
	f.Add("")

	f.Fuzz(func(t *testing.T, s string) {
		_, _ = class.ParseIdentity(s)
	})
}

// FuzzParseClass exercises the policy-class parser, including its query-string
// plugin/transformer requirement grammar.
func FuzzParseClass(f *testing.F) {
	f.Add("cel@v1")
	f.Add("cel@v1?plugin:semver=v1&transformer:protobom=v1")
	f.Add("cel@v1?plugin:=v1")
	f.Add("cel@v1?bogus:x=v1")
	f.Add("")

	f.Fuzz(func(t *testing.T, s string) {
		_, _ = class.ParseClass(s)
	})
}
