#include "catalog_stats.h"

CatalogStats::CatalogStats(FlatpakManager *manager, QObject *parent)
    : QObject(parent), m_manager(manager) {
    connect(manager, &FlatpakManager::popularityChanged, this, &CatalogStats::changed);
}
