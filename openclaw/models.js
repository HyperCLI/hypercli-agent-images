function parseCsv(env, name) {
  const raw = env[name]
  if (typeof raw !== "string") return []
  return [...new Set(raw.split(",").map((s) => s.trim()).filter(Boolean))]
}

function modelEntry(id, existingById) {
  const existing = existingById.get(id)
  if (existing && typeof existing === "object") return { ...existing, id }
  return { id, name: id }
}

function applyModelEnv(config, env) {
  const defaults = (((config.agents ||= {}).defaults ||= {}))
  const models = parseCsv(env, "HYPER_MODELS")
  if (models.length > 0) {
    const provider = (((config.models ||= {}).providers ||= {}).hypercli ||= {})
    const existingById = new Map(
      (Array.isArray(provider.models) ? provider.models : [])
        .filter((model) => model && typeof model === "object" && typeof model.id === "string")
        .map((model) => [model.id, model]),
    )
    provider.models = models.map((id) => modelEntry(id, existingById))
    defaults.model = { ...(defaults.model || {}), primary: `hypercli/${models[0]}` }
    defaults.models = Object.fromEntries(models.map((id) => [`hypercli/${id}`, { alias: id }]))
    defaults.modelPolicy = { ...(defaults.modelPolicy || {}), allow: models.map((id) => `hypercli/${id}`) }
  }

  const embeddingModels = parseCsv(env, "HYPER_EMBEDDING_MODELS")
  if (embeddingModels.length > 0) {
    const memorySearch = (defaults.memorySearch ||= {})
    memorySearch.model = embeddingModels[0]
    memorySearch.models = embeddingModels
  }
}

module.exports = { applyModelEnv }
