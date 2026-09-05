.pragma library

var MAX_APPLICATIONS = 128
var MAX_MATCHERS_PER_APPLICATION = 32
var MAX_APPLICATION_ID_CHARS = 128
var MAX_APPLICATION_NAME_CHARS = 256
var MAX_MATCHER_CHARS = 256

function boundedDisplayText(value, maximumLength) {
  var text = String(value === undefined || value === null ? "" : value)
    .replace(/[\u0000-\u001f\u007f]/g, " ")
  return text.length > maximumLength ? text.slice(0, maximumLength - 1) + "…" : text
}

function sanitizedMatcherList(values) {
  if (!(values instanceof Array)) return null
  if (values.length > MAX_MATCHERS_PER_APPLICATION) return null
  var result = []
  for (var index = 0; index < values.length; index++) {
    if (typeof values[index] !== "string" || !values[index]
        || values[index].length > MAX_MATCHER_CHARS
        || /[\u0000-\u001f\u007f]/.test(values[index]) || !values[index].trim()) return null
    result.push(values[index])
  }
  return result
}

function sanitizedApplications(values) {
  if (!(values instanceof Array) || values.length > MAX_APPLICATIONS) return null
  var result = []
  var ids = Object.create(null)
  for (var index = 0; index < values.length; index++) {
    var application = values[index]
    if (!application || typeof application !== "object" || application instanceof Array) return null
    if (typeof application.id !== "string" || !application.id
        || application.id.length > MAX_APPLICATION_ID_CHARS
        || /[\u0000-\u001f\u007f]/.test(application.id)
        || ids[application.id] === true) return null
    if (typeof application.name !== "string" || !application.name
        || application.name.length > MAX_APPLICATION_NAME_CHARS
        || /[\u0000-\u001f\u007f]/.test(application.name)
        || application.enabled === undefined || typeof application.enabled !== "boolean"
        || application.mode !== "double-press" || !application.match
        || typeof application.match !== "object" || application.match instanceof Array) return null
    var classes = sanitizedMatcherList(application.match.class)
    var initialClasses = sanitizedMatcherList(application.match.initialClass)
    if (classes === null || initialClasses === null || (!classes.length && !initialClasses.length)) return null
    ids[application.id] = true
    result.push({
      id: application.id,
      name: boundedDisplayText(application.name, MAX_APPLICATION_NAME_CHARS),
      enabled: application.enabled,
      match: { class: classes, initialClass: initialClasses }
    })
  }
  return result
}

function parseStatus(raw) {
  if (typeof raw !== "string" || !raw.trim()) return null
  var state
  try { state = JSON.parse(raw) } catch (error) { return null }
  if (!state || typeof state !== "object" || state instanceof Array
      || state.schemaVersion !== 1 || typeof state.enabled !== "boolean"
      || typeof state.confirmWindowMs !== "number" || !Number.isInteger(state.confirmWindowMs)
      || state.confirmWindowMs < 100 || state.confirmWindowMs > 999999) return null
  var applications = sanitizedApplications(state.protectedApplications)
  if (applications === null) return null
  return { enabled: state.enabled, applications: applications }
}
