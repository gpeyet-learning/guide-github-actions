---
title: "Variables, secrets et environnements"
weight: 40
---

## Les contextes GitHub Actions

Avant de parler de variables, il faut comprendre les **contextes**. Un contexte est un objet qui contient des informations sur l'exécution en cours. On y accède avec la syntaxe `${{ contexte.propriété }}`.

```mermaid
graph TD
    C[Contextes] --> github
    C --> env
    C --> vars
    C --> secrets
    C --> runner
    C --> job
    C --> steps
    C --> matrix
    github --> |sha, ref, actor, repo...| G1[Infos sur le déclencheur]
    runner --> |os, arch, temp...| R1[Infos sur la machine]
    secrets --> |clés masquées| S1[Données sensibles]
    vars --> |clés en clair| V1[Configuration non sensible]
```

### Le contexte `github`

Le plus utilisé. Il contient toutes les informations sur le run en cours :

| Expression                     | Valeur                                          |
|--------------------------------|-------------------------------------------------|
| `github.sha`                   | SHA du commit qui a déclenché le workflow       |
| `github.ref`                   | Référence (`refs/heads/main`)                   |
| `github.ref_name`              | Nom court (`main`, `v1.0.0`)                    |
| `github.event_name`            | Nom de l'événement (`push`, `pull_request`)     |
| `github.actor`                 | Login de l'utilisateur qui a déclenché          |
| `github.repository`            | `owner/repo`                                    |
| `github.repository_owner`      | `owner`                                         |
| `github.run_id`                | ID unique du run                                |
| `github.run_number`            | Numéro séquentiel du run (1, 2, 3…)             |

```yaml
- run: echo "Commit ${{ github.sha }} par ${{ github.actor }}"
```

### Le contexte `runner`

```yaml
- run: echo "OS : ${{ runner.os }}, Arch : ${{ runner.arch }}"
# Affiche : OS : Linux, Arch : X64
```

## Variables d'environnement

Il existe trois façons de définir une variable, selon sa portée :

### 1. Variables globales au workflow

```yaml
env:
  PYTHON_VERSION: "3.12"
  APP_NAME: "mon-app"

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - run: echo "$APP_NAME"          # mon-app
```

### 2. Variables locales au job

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    env:
      BUILD_ENV: production            # Disponible dans toutes les steps du job
    steps:
      - run: echo "$BUILD_ENV"
```

### 3. Variables locales à une step

```yaml
steps:
  - name: Deploy
    env:
      DEPLOY_TARGET: staging           # Disponible uniquement dans cette step
    run: echo "Déploiement sur $DEPLOY_TARGET"
```

### Variables d'environnement spéciales

GitHub injecte automatiquement plusieurs variables dans chaque step :

| Variable              | Description                                    |
|-----------------------|------------------------------------------------|
| `GITHUB_SHA`          | SHA du commit (équivalent de `github.sha`)     |
| `GITHUB_REF`          | Référence complète                             |
| `GITHUB_REPOSITORY`   | `owner/repo`                                   |
| `GITHUB_WORKSPACE`    | Chemin vers le dossier de travail du runner    |
| `GITHUB_OUTPUT`       | Fichier pour définir des outputs de step       |
| `GITHUB_ENV`          | Fichier pour définir des variables persistantes |

### Définir une variable persistante entre les steps

Pour qu'une variable définie dans une step soit disponible dans les steps **suivantes** du même job :

```yaml
steps:
  - name: Calculer la version
    run: echo "VERSION=1.2.3" >> $GITHUB_ENV

  - name: Utiliser la version
    run: echo "Je vais builder la version $VERSION"
```

La variable est ajoutée au fichier `$GITHUB_ENV` — un mécanisme de communication entre steps.

## Les variables de dépôt (`vars`)

Les **variables** (non sensibles) peuvent être configurées dans les paramètres du dépôt : **Settings → Secrets and variables → Actions → Variables**.

```yaml
steps:
  - run: echo "Déployer sur ${{ vars.DEPLOY_HOST }}"
```

Contrairement aux secrets, les variables sont visibles dans les logs. Elles sont idéales pour stocker des configurations : noms d'hôtes, régions, noms d'environnements.

## Les secrets

Un **secret** est une valeur chiffrée stockée côté GitHub. Elle est injectée dans le workflow sans jamais apparaître en clair dans les logs (GitHub la masque automatiquement).

### Créer un secret

**Settings → Secrets and variables → Actions → New repository secret**

- Nom : `DATABASE_URL`
- Valeur : `postgresql://user:password@host:5432/db`

### Utiliser un secret

```yaml
steps:
  - name: Se connecter à la base
    env:
      DATABASE_URL: ${{ secrets.DATABASE_URL }}
    run: python manage.py migrate
```

> Ne jamais écrire `run: echo ${{ secrets.MON_SECRET }}` — bien que GitHub masque la valeur dans les logs, c'est une mauvaise pratique qui peut exposer le secret si un outil intermédiaire capture stdout.

### Le secret `GITHUB_TOKEN`

Un secret spécial est **automatiquement disponible** dans chaque workflow sans configuration :

```yaml
- uses: actions/checkout@v4
  with:
    token: ${{ secrets.GITHUB_TOKEN }}
```

Ce token est généré à chaque run et expire à la fin. Il permet d'interagir avec l'API GitHub (créer des issues, commenter des PRs, publier des releases...) avec les permissions du workflow.

Les permissions par défaut peuvent être restreintes ou élargies :

```yaml
permissions:
  contents: read           # Lire le dépôt
  pull-requests: write     # Commenter les PRs
  packages: write          # Publier sur GHCR
```

## Les environnements de déploiement

Les **environnements** permettent de modéliser les cibles de déploiement (staging, production) et d'y associer :

- Des **secrets spécifiques** à l'environnement
- Des **variables** propres à l'environnement
- Des **règles de protection** (approbation manuelle, branches autorisées, délai d'attente)

### Créer un environnement

**Settings → Environments → New environment**

Créez deux environnements : `staging` et `production`. Pour `production`, activez la règle **Required reviewers** et ajoutez-vous comme reviewer.

### Utiliser un environnement dans un workflow

```yaml
jobs:
  deploy-staging:
    runs-on: ubuntu-latest
    environment: staging                # Référence l'environnement
    steps:
      - run: echo "Deploy sur ${{ vars.DEPLOY_HOST }}"
                                        # Utilise les vars de l'environnement staging

  deploy-production:
    runs-on: ubuntu-latest
    environment:
      name: production
      url: "https://api.monsite.com"    # URL affichée dans l'interface GitHub
    needs: deploy-staging
    steps:
      - run: echo "Deploy en production"
```

Quand un job référence l'environnement `production` avec la règle "Required reviewers", le workflow **se met en pause** et envoie une notification aux reviewers. Le run reprend uniquement après approbation manuelle.

```mermaid
sequenceDiagram
    participant W as Workflow
    participant G as GitHub
    participant H as Humain (reviewer)

    W->>G: Job deploy-production démarre
    G->>H: Notification : approbation requise
    G-->>W: En pause (waiting for review)
    H->>G: Approuve le déploiement
    G->>W: Reprise du job
    W->>W: Exécute les steps de déploiement
```

## Niveaux de secrets : repo, organisation, environnement

Les secrets peuvent être définis à trois niveaux :

```mermaid
graph TD
    O[Organisation<br/>github.com/orgs/mon-org] -->|hérités par| R1[Repo A]
    O -->|hérités par| R2[Repo B]
    R1 -->|spécifiques| E1[Env: staging]
    R1 -->|spécifiques| E2[Env: production]
```

- **Organisation** : disponibles dans tous les repos de l'org (avec filtrage possible)
- **Dépôt** : disponibles dans tous les workflows du repo
- **Environnement** : disponibles uniquement quand le job référence cet environnement

Priorité : **Environnement > Dépôt > Organisation**

## Bonnes pratiques

- **Rotation** : changez régulièrement les secrets sensibles (tokens API, mots de passe).
- **Principe de moindre privilège** : donnez aux tokens uniquement les permissions nécessaires.
- **Jamais dans le code** : vérifiez votre historique git avant d'ajouter un secret — un secret committé dans git doit être considéré comme compromis, même si supprimé ensuite.
- **Variables vs secrets** : utilisez `vars` pour les valeurs non sensibles (noms d'hôtes, régions) et `secrets` pour les valeurs confidentielles (tokens, mots de passe).

> **Exercice** : Dans le dépôt `mon-app`, créez un secret `API_KEY` avec la valeur `my-super-secret-key`. Ajoutez un environnement `staging`. Dans le workflow `ci.yml`, ajoutez un job `check-secrets` qui référence l'environnement `staging` et affiche un message en utilisant la variable d'environnement `API_KEY` (sans afficher sa valeur).

<details>
<summary>Solution</summary>

Dans les Settings du dépôt :

1. **Settings → Secrets and variables → Actions → New repository secret**
   - Name: `API_KEY`, Value: `my-super-secret-key`

2. **Settings → Environments → New environment**
   - Name: `staging`

Dans le workflow :

```yaml
  check-secrets:
    runs-on: ubuntu-latest
    environment: staging
    steps:
      - name: Vérifier que le secret est disponible
        env:
          API_KEY: ${{ secrets.API_KEY }}
        run: |
          if [ -n "$API_KEY" ]; then
            echo "Le secret API_KEY est bien configuré (longueur : ${#API_KEY} caractères)"
          else
            echo "ERREUR : le secret API_KEY est absent"
            exit 1
          fi
```

La condition `[ -n "$API_KEY" ]` vérifie que la variable n'est pas vide sans l'afficher. `${#API_KEY}` affiche la longueur sans révéler la valeur.

Dans les logs GitHub, si vous essayez d'afficher la valeur directement, elle sera remplacée par `***`.

</details>
