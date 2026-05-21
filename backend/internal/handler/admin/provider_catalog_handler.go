package admin

import (
	"github.com/Wei-Shaw/sub2api/internal/domain"
	"github.com/Wei-Shaw/sub2api/internal/pkg/response"

	"github.com/gin-gonic/gin"
)

// ProviderCatalogHandler serves the canonical upstream vendor preset table.
type ProviderCatalogHandler struct{}

// NewProviderCatalogHandler creates a ProviderCatalogHandler.
func NewProviderCatalogHandler() *ProviderCatalogHandler {
	return &ProviderCatalogHandler{}
}

// List returns all provider presets (no secrets).
// GET /api/v1/admin/provider-catalog
func (h *ProviderCatalogHandler) List(c *gin.Context) {
	response.Success(c, domain.GetProviderCatalog())
}
