package router

import (
	"context"
	"fmt"
	"sync"
	"time"
)

// Route defines a single routing rule in the execution table.
type Route struct {
	Backend      string        `yaml:"backend"`
	Conditions   []string      `yaml:"when"`
	FailMode     string        `yaml:"fail_mode"`
	Timeout      time.Duration `yaml:"timeout"`
	Retries      int           `yaml:"retries"`
	Capabilities []string      `yaml:"capabilities"`
}

// Verdict represents the outcome of a review pass.
type Verdict string

const (
	VerdictApproved       Verdict = "APPROVED"
	VerdictChangesReq     Verdict = "CHANGES_REQUIRED"
	VerdictDecisionNeeded Verdict = "DECISION_NEEDED"
	VerdictSkipped        Verdict = "SKIPPED"
)

// ReviewResult holds structured output from a backend.
type ReviewResult struct {
	Verdict  Verdict   `json:"verdict"`
	Findings []Finding `json:"findings"`
	Summary  string    `json:"summary"`
}

// Finding represents a single code review finding.
type Finding struct {
	Severity string `json:"severity"`
	File     string `json:"file"`
	Line     int    `json:"line"`
	Message  string `json:"message"`
}

// BackendFunc is the signature for registered backends.
type BackendFunc func(ctx context.Context, input string) (*ReviewResult, error)

// RouteTable manages route evaluation and execution.
type RouteTable struct {
	routes     []Route
	backends   map[string]BackendFunc
	conditions map[string]func(ctx context.Context) bool
	mu         sync.RWMutex
}

// NewRouteTable creates a route table with the given routes.
func NewRouteTable(routes []Route) *RouteTable {
	return &RouteTable{
		routes:     routes,
		backends:   make(map[string]BackendFunc),
		conditions: make(map[string]func(ctx context.Context) bool),
	}
}

// RegisterBackend adds a named backend handler.
func (rt *RouteTable) RegisterBackend(name string, fn BackendFunc) {
	rt.mu.Lock()
	defer rt.mu.Unlock()
	rt.backends[name] = fn
}

// Execute runs through routes in order, returning the first successful result.
func (rt *RouteTable) Execute(ctx context.Context, input string) (*ReviewResult, error) {
	rt.mu.RLock()
	defer rt.mu.RUnlock()

	for i, route := range rt.routes {
		if !rt.evaluateConditions(ctx, route.Conditions) {
			continue
		}

		fn, ok := rt.backends[route.Backend]
		if !ok {
			if route.FailMode == "hard_fail" {
				return nil, fmt.Errorf("unknown backend: %s", route.Backend)
			}
			continue
		}

		var result *ReviewResult
		var err error
		for attempt := 0; attempt <= route.Retries; attempt++ {
			routeCtx, cancel := context.WithTimeout(ctx, route.Timeout)
			result, err = fn(routeCtx, input)
			cancel()
			if err == nil {
				break
			}
			fmt.Printf("[route %d] attempt %d failed: %v\n", i, attempt+1, err)
		}

		if err != nil {
			if route.FailMode == "hard_fail" {
				return nil, fmt.Errorf("backend %s hard-failed: %w", route.Backend, err)
			}
			continue
		}

		return result, nil
	}

	return nil, fmt.Errorf("all routes exhausted")
}

func (rt *RouteTable) evaluateConditions(ctx context.Context, conds []string) bool {
	for _, name := range conds {
		fn, ok := rt.conditions[name]
		if !ok || !fn(ctx) {
			return false
		}
	}
	return true
}
