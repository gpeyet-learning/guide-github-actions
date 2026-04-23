---
title: "Actions et Marketplace"
weight: 30
---

## Qu'est-ce qu'une action ?

Dans le chapitre précédent, le workflow `ci.yml` utilisait uniquement des commandes `run`. Il tournait, affichait des informations — mais il n'avait pas accès au code du dépôt. Pour cloner le dépôt manuellement, il faudrait écrire :

```yaml
run: |
  git config --global url."https://x-access-token:${{ github.token }}@github.com/".insteadOf "https://github.com/"
  git clone https://github.com/${{ github.repository }}.git .
  git checkout ${{ github.sha }}
```

Avec une action, on écrit simplement :

```yaml
uses: actions/checkout@v6
```

C'est la valeur fondamentale des actions : **l'abstraction**. Quelqu'un a résolu ce problème une fois, correctement, et tout le monde en bénéficie. Une **action** est une unité de code réutilisable — l'équivalent d'une fonction dans un workflow.

## Types d'actions

Il existe trois types d'actions selon leur implémentation :

| Type                  | Langage          | Vitesse                    | Usage typique                   |
| --------------------- | ---------------- | -------------------------- | ------------------------------- |
| JavaScript/TypeScript | Node.js          | Rapide                     | Actions légères, appels API     |
| Docker container      | N'importe lequel | Plus lent (image à puller) | Environnements spécialisés      |
| Composite             | Steps YAML       | Variable                   | Réutiliser des steps entre jobs |

## Le Marketplace GitHub

Le [Marketplace GitHub Actions](https://github.com/marketplace?type=actions) recense des milliers d'actions développées par GitHub, des entreprises et la communauté. La recherche se fait directement dans l'interface GitHub ou sur le site du marketplace.

### Actions officielles GitHub (`actions/*`)

Ces actions sont maintenues par GitHub et constituent les briques de base de tout workflow :

| Action                      | Rôle                                         |
| --------------------------- | -------------------------------------------- |
| `actions/checkout`          | Cloner le dépôt dans le runner               |
| `actions/setup-python`      | Installer une version de Python              |
| `actions/setup-node`        | Installer une version de Node.js             |
| `actions/setup-go`          | Installer une version de Go                  |
| `actions/setup-java`        | Installer une version de Java                |
| `actions/cache`             | Mettre en cache des dossiers entre les runs  |
| `actions/upload-artifact`   | Sauvegarder des fichiers produits par un job |
| `actions/download-artifact` | Récupérer des fichiers d'un autre job        |

### Référencer une action

La syntaxe est toujours : `<propriétaire>/<nom>@<version>`

```yaml
uses: actions/checkout@v6          # Tag semver (recommandé)
uses: actions/checkout@main        # Branche (déconseillé en prod)
uses: actions/checkout@abc1234     # SHA de commit (le plus strict)
```

> **Bonne pratique de sécurité** : en production, référencez les actions par leur SHA de commit plutôt que par un tag. Un tag peut être réécrit (tag flotant), un SHA est immuable.

```yaml
# Plus sécurisé :
uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2
```

## Passer des paramètres avec `with`

Les actions acceptent des paramètres via la section `with` :

```yaml
- uses: actions/setup-python@v5
  with:
    python-version: "3.12"
    cache: "pip" # Active le cache pip automatiquement
```

```yaml
- uses: actions/setup-node@v4
  with:
    node-version: "20"
    cache: "npm"
```

Les paramètres disponibles sont documentés dans le README de chaque action sur GitHub.

## Lire les outputs d'une action

Certaines actions produisent des **outputs** — des valeurs calculées que les steps suivantes peuvent consommer.

```yaml
steps:
  - name: Récupérer la version de l'application
    id: version                           # ← identifiant obligatoire pour lire l'output
    run: echo "app-version=1.2.3" >> $GITHUB_OUTPUT

  - name: Utiliser la version
    run: echo "Version : ${{ steps.version.outputs.app-version }}"
```

La syntaxe `$GITHUB_OUTPUT` est la façon moderne de définir un output (l'ancienne méthode `::set-output::` est dépréciée).

## Actions locales

On peut définir ses propres actions directement dans le dépôt. Deux cas d'usage :

### Composite action locale

Créez le fichier `.github/actions/setup-python-env/action.yml` :

```yaml
# .github/actions/setup-python-env/action.yml
name: "Setup Python Environment"
description: "Installe Python et les dépendances du projet"

inputs:
  python-version:
    description: "Version Python à installer"
    default: "3.12"

runs:
  using: "composite"
  steps:
    - uses: actions/setup-python@v5
      with:
        python-version: ${{ inputs.python-version }}
        cache: pip

    - name: Installer les dépendances
      shell: bash
      run: |
        pip install -r requirements.txt
        pip install -r requirements-dev.txt
```

Utilisation dans un workflow :

```yaml
steps:
  - uses: actions/checkout@v6
  - uses: ./.github/actions/setup-python-env
    with:
      python-version: "3.12"
```

Le chemin `./.github/actions/setup-python-env` est relatif à la racine du dépôt.

## Les actions les plus courantes en détail

### `actions/checkout@v6`

```yaml
- uses: actions/checkout@v6
  with:
    # Par défaut : checkout du commit qui a déclenché le workflow
    fetch-depth: 0 # 0 = historique complet (utile pour semantic-release)
    token: ${{ secrets.PAT }} # Token avec plus de permissions que le défaut
    submodules: recursive # Initialiser les sous-modules Git
```

Sans `actions/checkout`, le répertoire de travail du runner est vide.

### `actions/setup-python@v5`

```yaml
- uses: actions/setup-python@v5
  with:
    python-version: "3.12"
    cache: "pip" # Met en cache ~/.cache/pip entre les runs
    cache-dependency-path: |
      requirements.txt
      requirements-dev.txt
```

L'option `cache` accélère considérablement les builds en évitant de re-télécharger les packages à chaque run.

### `actions/cache@v4`

Pour des besoins de cache plus fins :

```yaml
- uses: actions/cache@v4
  with:
    path: ~/.cache/pip
    key: ${{ runner.os }}-pip-${{ hashFiles('requirements*.txt') }}
    restore-keys: |
      ${{ runner.os }}-pip-
```

La `key` détermine si le cache est valide. Si la clé exacte existe, le cache est restauré. Sinon, les `restore-keys` sont tentées dans l'ordre (correspondance partielle). Le cache est sauvegardé à la fin du job si la clé exacte n'existait pas.

## Actions tierces populaires

### Publication sur PyPI / npm

```yaml
# Publication sur PyPI
- uses: pypa/gh-action-pypi-publish@release/v1
  with:
    password: ${{ secrets.PYPI_API_TOKEN }}
```

```yaml
# Publication sur npm
- uses: JS-DevTools/npm-publish@v3
  with:
    token: ${{ secrets.NPM_TOKEN }}
```

### Notifications Slack

```yaml
- uses: slackapi/slack-github-action@v2
  with:
    channel-id: "C1234567890"
    slack-message: "Déploiement de ${{ github.repository }} terminé !"
  env:
    SLACK_BOT_TOKEN: ${{ secrets.SLACK_BOT_TOKEN }}
```

### Docker Build & Push

```yaml
- uses: docker/setup-buildx-action@v3

- uses: docker/login-action@v3
  with:
    registry: ghcr.io
    username: ${{ github.actor }}
    password: ${{ secrets.GITHUB_TOKEN }}

- uses: docker/build-push-action@v6
  with:
    push: true
    tags: ghcr.io/${{ github.repository }}:latest
```

## Évaluer la fiabilité d'une action tierce

Avant d'utiliser une action du marketplace, vérifiez :

1. **Le badge "Verified creator"** : l'auteur est une organisation vérifiée.
2. **Le nombre d'étoiles et de forks** : indique l'adoption.
3. **La date du dernier commit** : une action non maintenue peut devenir un risque.
4. **Le code source** : lisez le `action.yml` et le code — une action qui exécute `curl | bash` vers un serveur inconnu est un red flag.

> **Exercice** : Faites évoluer le workflow `ci.yml` de `mon-app` construit au chapitre précédent. Remplacez les deux jobs `info` et `check` par un job unique `build` qui :
>
> 1. Clone le code du dépôt avec `actions/checkout@v6`.
> 2. Active Docker Buildx avec `docker/setup-buildx-action@v3`.
> 3. Construit l'image Docker sans la pousser, en activant le cache GitHub Actions.

<details>
<summary>Solution</summary>

```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  build:
    name: "Build Docker"
    runs-on: ubuntu-latest
    steps:
      - name: Cloner le code
        uses: actions/checkout@v6

      - name: Configurer Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Vérifier que l'image se build
        uses: docker/build-push-action@v6
        with:
          context: .
          push: false
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

Comparez avec le workflow du chapitre précédent :

- Sans `actions/checkout@v6`, le runner démarre avec un répertoire de travail **vide** — le `Dockerfile` n'est pas accessible.
- `docker/setup-buildx-action@v3` active BuildKit, qui apporte le cache de couches et le support multi-arch. Sans cette action, il faudrait configurer BuildKit à la main.
- `push: false` construit l'image localement sans la publier — suffisant pour valider que le `Dockerfile` est correct à chaque push.
- `cache-from/cache-to: type=gha` met en cache les couches Docker entre les runs. Le premier run construit tout depuis zéro ; les runs suivants réutilisent les couches inchangées — gain typique de 30 à 60 secondes sur un projet réel.

</details>
