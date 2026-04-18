---
title: "Sécurité avancée de la chaîne CI/CD"
weight: 120
---

## Sécuriser la supply chain logicielle

La **supply chain attack** consiste à compromettre un projet via ses dépendances plutôt qu'en attaquant le projet directement. L'attaque SolarWinds (2020) ou l'incident `xz-utils` (2024) ont mis en lumière ce vecteur.

GitHub Actions offre plusieurs outils pour sécuriser cette chaîne.

## CodeQL — Analyse statique de sécurité

[CodeQL](https://codeql.github.com/) est le moteur d'analyse statique de GitHub. Il détecte les vulnérabilités de sécurité dans le code : injections SQL, XSS, traversée de répertoire, etc.

### Configurer CodeQL

```yaml
# .github/workflows/codeql.yml
name: CodeQL Analysis

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
  schedule:
    - cron: "0 2 * * 1"      # Scan hebdomadaire le lundi à 2h

permissions:
  contents: read
  security-events: write     # Pour publier les résultats dans l'onglet Security

jobs:
  analyze:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        # Adaptez à votre stack : python, javascript, java, go, ruby, swift, cpp...
        language: [python, javascript, java]

    steps:
      - uses: actions/checkout@v6

      - uses: github/codeql-action/init@v3
        with:
          languages: ${{ matrix.language }}
          queries: security-and-quality    # Requêtes de sécurité + qualité

      - uses: github/codeql-action/autobuild@v3    # Build automatique si nécessaire

      - uses: github/codeql-action/analyze@v3
        with:
          category: "/language:${{ matrix.language }}"
```

Les résultats apparaissent dans **Security → Code scanning alerts**. Chaque alerte inclut le fichier, la ligne, une explication de la vulnérabilité et des suggestions de correction.

## Dependabot — Mises à jour automatiques

Dependabot surveille les dépendances et crée des PRs automatiques quand des mises à jour sont disponibles, notamment des correctifs de sécurité.

### Configurer Dependabot

```yaml
# .github/dependabot.yml
version: 2
updates:
  # Activez uniquement les écosystèmes pertinents pour votre stack :

  # Python
  - package-ecosystem: "pip"
    directory: "/"
    schedule:
      interval: "weekly"
      day: "monday"
      time: "09:00"
      timezone: "Europe/Paris"
    open-pull-requests-limit: 5
    commit-message:
      prefix: "chore(deps)"
    labels:
      - "dependencies"
      - "automated"

  # Node.js / Angular
  # - package-ecosystem: "npm"
  #   directory: "/"
  #   schedule:
  #     interval: "weekly"

  # Java (Maven)
  # - package-ecosystem: "maven"
  #   directory: "/"
  #   schedule:
  #     interval: "weekly"

  # PHP
  # - package-ecosystem: "composer"
  #   directory: "/"
  #   schedule:
  #     interval: "weekly"

  # GitHub Actions (universel — à toujours activer)
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
    commit-message:
      prefix: "chore(deps)"
```

Dependabot crée des PRs comme :
- `chore(deps): bump requests from 2.31.0 to 2.32.0`
- `chore(deps): bump actions/checkout from v3 to v4`

### Auto-merger les updates de Dependabot

Pour les updates mineures ou de patch (pas les majeures), on peut configurer un auto-merge après passage de la CI :

```yaml
# .github/workflows/dependabot-auto-merge.yml
name: Auto-merge Dependabot PRs

on:
  pull_request:

permissions:
  contents: write
  pull-requests: write

jobs:
  auto-merge:
    runs-on: ubuntu-latest
    # Seulement les PRs Dependabot de type patch/minor
    if: |
      github.actor == 'dependabot[bot]' &&
      (contains(github.event.pull_request.title, 'bump') &&
       !startsWith(github.event.pull_request.title, 'chore(deps): bump') == false)
    steps:
      - uses: actions/checkout@v6

      - name: Récupérer les métadonnées Dependabot
        id: meta
        uses: dependabot/fetch-metadata@v2
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}

      - name: Auto-approuver et merger si patch/minor
        if: |
          steps.meta.outputs.update-type == 'version-update:semver-patch' ||
          steps.meta.outputs.update-type == 'version-update:semver-minor'
        run: gh pr merge --auto --squash "$PR_URL"
        env:
          PR_URL: ${{ github.event.pull_request.html_url }}
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

## Signé des images Docker — cosign

[cosign](https://github.com/sigstore/cosign) permet de signer les images Docker pour garantir leur authenticité. Un utilisateur peut vérifier qu'une image a bien été produite par votre pipeline CI.

```yaml
  sign-image:
    needs: build-push
    runs-on: ubuntu-latest
    permissions:
      id-token: write          # Pour OIDC keyless signing
      packages: write

    steps:
      - uses: sigstore/cosign-installer@v3

      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Signer l'image
        run: |
          cosign sign --yes \
            ghcr.io/${{ github.repository }}@${{ needs.build-push.outputs.digest }}
```

La vérification côté utilisateur :

```bash
cosign verify \
  --certificate-identity "https://github.com/mon-org/mon-app/.github/workflows/docker.yml@refs/heads/main" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  ghcr.io/mon-org/mon-app:latest
```

## SBOM — Inventaire des composants

Un **Software Bill of Materials (SBOM)** est un inventaire exhaustif des composants d'un logiciel. Il permet d'évaluer rapidement l'impact d'une nouvelle CVE sur vos projets.

```yaml
      - name: Générer le SBOM
        uses: anchore/sbom-action@v0
        with:
          image: ghcr.io/${{ github.repository }}:${{ steps.meta.outputs.version }}
          format: spdx-json
          output-file: sbom.spdx.json

      - name: Uploader le SBOM comme artifact
        uses: actions/upload-artifact@v4
        with:
          name: sbom
          path: sbom.spdx.json

      - name: Attacher le SBOM à la release
        if: startsWith(github.ref, 'refs/tags/v')
        run: gh release upload ${{ github.ref_name }} sbom.spdx.json
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

## Scan de vulnérabilités sur l'image Docker

[Trivy](https://github.com/aquasecurity/trivy) scanne les images Docker pour détecter les CVEs dans les packages du système et les dépendances applicatives.

```yaml
  scan-image:
    needs: build-push
    runs-on: ubuntu-latest
    permissions:
      security-events: write
    steps:
      - name: Scanner l'image avec Trivy
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: ghcr.io/${{ github.repository }}:${{ needs.build-push.outputs.image-tag }}
          format: "sarif"
          output: "trivy-results.sarif"
          severity: "CRITICAL,HIGH"
          exit-code: "1"              # Échouer si des CVEs critiques/hautes sont trouvées

      - name: Uploader les résultats vers GitHub Security
        if: always()
        uses: github/codeql-action/upload-sarif@v3
        with:
          sarif_file: "trivy-results.sarif"
```

Les résultats apparaissent dans **Security → Code scanning alerts**, aux côtés des alertes CodeQL.

## Secret scanning

GitHub scanne automatiquement tous les commits poussés à la recherche de secrets (tokens AWS, clés API, certificats...). Si un secret est détecté :

1. **L'alerte apparaît** dans Security → Secret scanning alerts.
2. **Le partenaire est notifié** : GitHub a des accords avec AWS, GitHub, Slack, etc. pour révoquer automatiquement les secrets détectés.
3. **Vous êtes notifié** par email.

Pour les dépôts privés, activez le secret scanning : **Settings → Security → Secret scanning → Enable**.

### Push protection

La **push protection** bloque les commits qui contiennent des secrets **avant** qu'ils soient poussés :

**Settings → Security → Secret scanning → Push protection → Enable**

Si un développeur tente de pousser un commit avec un secret, le push est rejeté avec un message explicatif et un lien pour signaler un faux positif.

> **Exercice** : Activez CodeQL et Dependabot sur `mon-app`. Configurez Dependabot pour mettre à jour les dépendances pip et les GitHub Actions chaque semaine. Ajoutez un scan Trivy dans le workflow Docker qui échoue en cas de CVE critique. Vérifiez dans l'onglet Security que les alertes CodeQL apparaissent.

<details>
<summary>Solution</summary>

1. Créez `.github/dependabot.yml` avec la configuration pip + github-actions ci-dessus.

2. Créez `.github/workflows/codeql.yml` avec la configuration CodeQL ci-dessus.

3. Ajoutez le job `scan-image` au workflow `docker.yml`.

4. Poussez les changements :

```bash
git add .github/
git commit -m "ci: add CodeQL, Dependabot and Trivy scanning"
git push origin main
```

5. Vérifications :
   - Onglet **Security → Code scanning** : résultats CodeQL dans quelques minutes
   - Onglet **Security → Dependabot alerts** : vulnérabilités connues dans les dépendances
   - Onglet **Actions** : le workflow CodeQL tourne en parallèle du CI normal

Si Trivy trouve des CVEs critiques dans l'image (ce qui peut arriver avec `python:3.12-slim`), utilisez `python:3.12-slim` avec les derniers patchs ou ajoutez des exceptions pour les faux positifs :

```yaml
        with:
          ignore-unfixed: true    # Ignorer les CVE sans correctif disponible
```

</details>
