package cmd

import (
	"errors"
	"testing"
	"time"
)

func TestCalculateBackoff(t *testing.T) {
	tests := []struct {
		name       string
		strategy   string
		base       time.Duration
		multiplier float64
		max        time.Duration
		attempt    int
		expected   time.Duration
	}{
		{
			name:       "exponential backoff attempt 0",
			strategy:   "exponential",
			base:       2 * time.Second,
			multiplier: 2.0,
			max:        60 * time.Second,
			attempt:    0,
			expected:   2 * time.Second,
		},
		{
			name:       "exponential backoff attempt 1",
			strategy:   "exponential",
			base:       2 * time.Second,
			multiplier: 2.0,
			max:        60 * time.Second,
			attempt:    1,
			expected:   4 * time.Second,
		},
		{
			name:       "exponential backoff attempt 2",
			strategy:   "exponential",
			base:       2 * time.Second,
			multiplier: 2.0,
			max:        60 * time.Second,
			attempt:    2,
			expected:   8 * time.Second,
		},
		{
			name:       "exponential backoff capped at max",
			strategy:   "exponential",
			base:       2 * time.Second,
			multiplier: 2.0,
			max:        10 * time.Second,
			attempt:    5,
			expected:   10 * time.Second,
		},
		{
			name:       "linear backoff attempt 0",
			strategy:   "linear",
			base:       2 * time.Second,
			multiplier: 2.0,
			max:        60 * time.Second,
			attempt:    0,
			expected:   2 * time.Second,
		},
		{
			name:       "linear backoff attempt 1",
			strategy:   "linear",
			base:       2 * time.Second,
			multiplier: 2.0,
			max:        60 * time.Second,
			attempt:    1,
			expected:   4 * time.Second,
		},
		{
			name:       "linear backoff attempt 2",
			strategy:   "linear",
			base:       2 * time.Second,
			multiplier: 2.0,
			max:        60 * time.Second,
			attempt:    2,
			expected:   6 * time.Second,
		},
		{
			name:       "constant backoff",
			strategy:   "constant",
			base:       5 * time.Second,
			multiplier: 2.0,
			max:        60 * time.Second,
			attempt:    0,
			expected:   5 * time.Second,
		},
		{
			name:       "constant backoff attempt 5",
			strategy:   "constant",
			base:       5 * time.Second,
			multiplier: 2.0,
			max:        60 * time.Second,
			attempt:    5,
			expected:   5 * time.Second,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Set module-level variables
			backoffStrategy = tt.strategy
			backoffBase = tt.base
			backoffMultiplier = tt.multiplier
			backoffMax = tt.max

			result := calculateBackoff(tt.attempt)
			if result != tt.expected {
				t.Errorf("calculateBackoff(%d) = %v, expected %v", tt.attempt, result, tt.expected)
			}
		})
	}
}

func TestIsRetriableError(t *testing.T) {
	tests := []struct {
		name     string
		err      error
		expected bool
	}{
		{
			name:     "nil error",
			err:      nil,
			expected: false,
		},
		{
			name:     "connection refused",
			err:      errors.New("connection refused"),
			expected: true,
		},
		{
			name:     "timeout",
			err:      errors.New("timeout waiting for response"),
			expected: true,
		},
		{
			name:     "no such host",
			err:      errors.New("no such host"),
			expected: true,
		},
		{
			name:     "network unreachable",
			err:      errors.New("network is unreachable"),
			expected: true,
		},
		{
			name:     "connection reset",
			err:      errors.New("connection reset by peer"),
			expected: true,
		},
		{
			name:     "502 bad gateway",
			err:      errors.New("API error (status 502): bad gateway"),
			expected: true,
		},
		{
			name:     "503 service unavailable",
			err:      errors.New("API error (status 503): service unavailable"),
			expected: true,
		},
		{
			name:     "504 gateway timeout",
			err:      errors.New("API error (status 504): gateway timeout"),
			expected: true,
		},
		{
			name:     "container startup failure",
			err:      errors.New("failed to start container"),
			expected: true,
		},
		{
			name:     "stream connection error",
			err:      errors.New("failed to connect to stream"),
			expected: true,
		},
		{
			name:     "validation error (not retriable)",
			err:      errors.New("validation failed: topology errors found"),
			expected: false,
		},
		{
			name:     "400 bad request (not retriable)",
			err:      errors.New("API error (status 400): bad request"),
			expected: false,
		},
		{
			name:     "401 unauthorized (not retriable)",
			err:      errors.New("API error (status 401): unauthorized"),
			expected: false,
		},
		{
			name:     "403 forbidden (not retriable)",
			err:      errors.New("API error (status 403): forbidden"),
			expected: false,
		},
		{
			name:     "404 not found (not retriable)",
			err:      errors.New("API error (status 404): not found"),
			expected: false,
		},
		{
			name:     "generic error (not retriable)",
			err:      errors.New("something went wrong"),
			expected: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := isRetriableError(tt.err)
			if result != tt.expected {
				t.Errorf("isRetriableError(%v) = %v, expected %v", tt.err, result, tt.expected)
			}
		})
	}
}
