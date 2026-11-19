import { useEffect, useState } from 'react'

type BackendPayload = Record<string, unknown>

const backendUrl = 'http://127.0.0.1:8000/'

function App() {
  const [data, setData] = useState<BackendPayload | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    const controller = new AbortController()

    fetch(backendUrl, { signal: controller.signal })
      .then(async (response) => {
        if (!response.ok) {
          throw new Error(`Backend responded with ${response.status}`)
        }
        return (await response.json()) as BackendPayload
      })
      .then((payload) => {
        setData(payload)
        setError(null)
      })
      .catch((err: unknown) => {
        if (err instanceof DOMException && err.name === 'AbortError') {
          return
        }
        setError(err instanceof Error ? err.message : 'Failed to load backend')
      })

    return () => controller.abort()
  }, [])

  if (error) {
    return <p>{error}</p>
  }

  if (!data) {
    return <p>Loading backend…</p>
  }

  return (
    <dl>
      {Object.entries(data).map(([key, value]) => (
        <div key={key}>
          <dt>{key}</dt>
          <dd>{typeof value === 'string' ? value : JSON.stringify(value)}</dd>
        </div>
      ))}
    </dl>
  )
}

export default App
