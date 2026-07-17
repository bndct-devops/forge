import { useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { useAuth } from '../contexts/AuthContext'

/** Lands here from the OIDC callback redirect with the JWT in the URL
 *  fragment; scrub it from the address bar immediately, then hydrate. */
export default function OidcCallbackPage() {
  const { loginWithToken } = useAuth()
  const navigate = useNavigate()

  useEffect(() => {
    const token = new URLSearchParams(window.location.hash.slice(1)).get('token')
    history.replaceState(null, '', window.location.pathname)
    if (!token) {
      navigate('/login?sso_error=exchange', { replace: true })
      return
    }
    loginWithToken(token)
      .then(() => navigate('/', { replace: true }))
      .catch(() => navigate('/login?sso_error=exchange', { replace: true }))
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  return (
    <div className="flex h-full items-center justify-center text-sm text-muted-foreground">
      Signing you in…
    </div>
  )
}
