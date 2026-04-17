---
title: "Conditions et expressions"
weight: 80
---

## Le langage d'expressions

GitHub Actions possède un mini-langage d'expressions qui permet d'évaluer des conditions, accéder aux contextes et appeler des fonctions. La syntaxe est `${{ expression }}`.

### Opérateurs

| Opérateur | Description              | Exemple                                    |
|-----------|--------------------------|--------------------------------------------|
| `==`      | Égalité                  | `github.ref == 'refs/heads/main'`         |
| `!=`      | Inégalité                | `github.event_name != 'pull_request'`     |
| `&&`      | ET logique               | `a && b`                                   |
| `\|\|`    | OU logique               | `a \|\| b`                                 |
| `!`       | NON logique              | `!cancelled()`                             |
| `>`       | Supérieur                | `steps.build.outputs.exit-code > 0`       |

### Fonctions intégrées

| Fonction                        | Description                                              |
|---------------------------------|----------------------------------------------------------|
| `contains(search, item)`        | Vrai si `search` contient `item`                        |
| `startsWith(str, prefix)`       | Vrai si `str` commence par `prefix`                     |
| `endsWith(str, suffix)`         | Vrai si `str` finit par `suffix`                        |
| `format(str, ...args)`          | Formatage de chaîne (`{0}`, `{1}`…)                     |
| `join(array, separator)`        | Joindre un tableau en chaîne                            |
| `toJson(value)`                 | Convertir en JSON                                       |
| `fromJson(string)`              | Parser du JSON                                          |
| `hashFiles(path)`               | Hash SHA-256 des fichiers correspondant au pattern      |

### Fonctions de statut

Ces fonctions s'utilisent dans les conditions `if:` pour réagir au statut du job ou des steps précédents :

| Fonction           | Vrai si...                                                              |
|--------------------|-------------------------------------------------------------------------|
| `success()`        | Toutes les steps précédentes ont réussi (comportement par défaut)       |
| `failure()`        | Au moins une step précédente a échoué                                   |
| `cancelled()`      | Le workflow a été annulé                                                |
| `always()`         | Toujours (même en cas d'échec ou d'annulation)                          |

## Conditions sur les steps

La propriété `if:` détermine si une step doit s'exécuter :

```yaml
steps:
  - name: Publier sur PyPI (seulement sur tag)
    if: startsWith(github.ref, 'refs/tags/v')
    run: python -m twine upload dist/*

  - name: Nettoyer en cas d'échec
    if: failure()
    run: rm -rf /tmp/build-cache

  - name: Notifier Slack (toujours, même si annulé)
    if: always()
    run: echo "Notification envoyée"

  - name: Déployer en staging (pas sur PR externe)
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    run: ./deploy.sh staging
```

## Conditions sur les jobs

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - run: echo "build"

  deploy-staging:
    needs: build
    if: github.event_name == 'push'       # Ne déploie pas sur les PRs
    runs-on: ubuntu-latest
    steps:
      - run: echo "deploy staging"

  deploy-production:
    needs: deploy-staging
    # Déployer en prod seulement sur main avec un tag
    if: |
      github.ref == 'refs/heads/main' &&
      startsWith(github.event.head_commit.message, 'release:')
    runs-on: ubuntu-latest
    steps:
      - run: echo "deploy production"
```

## Pattern : déclencher uniquement si des fichiers pertinents ont changé

Dans un monorepo, on veut souvent n'exécuter un pipeline que si son code a changé. Le filtre `paths` sur l'événement `push` gère le cas simple. Pour plus de contrôle dans un job :

```yaml
jobs:
  detect-changes:
    runs-on: ubuntu-latest
    outputs:
      api-changed: ${{ steps.changes.outputs.api }}
      frontend-changed: ${{ steps.changes.outputs.frontend }}
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 2               # Besoin du commit précédent pour comparer

      - uses: dorny/paths-filter@v3
        id: changes
        with:
          filters: |
            api:
              - 'api/**'
              - 'shared/**'
            frontend:
              - 'frontend/**'
              - 'shared/**'

  test-api:
    needs: detect-changes
    if: needs.detect-changes.outputs.api-changed == 'true'
    runs-on: ubuntu-latest
    steps:
      - run: echo "Tests API"

  test-frontend:
    needs: detect-changes
    if: needs.detect-changes.outputs.frontend-changed == 'true'
    runs-on: ubuntu-latest
    steps:
      - run: echo "Tests Frontend"
```

## Accéder aux outputs d'autres jobs

Les outputs d'un job sont accessibles via le contexte `needs` :

```yaml
jobs:
  prepare:
    runs-on: ubuntu-latest
    outputs:
      version: ${{ steps.version.outputs.value }}
      sha-short: ${{ steps.sha.outputs.value }}
    steps:
      - id: version
        run: echo "value=$(cat VERSION)" >> $GITHUB_OUTPUT

      - id: sha
        run: echo "value=${GITHUB_SHA::8}" >> $GITHUB_OUTPUT

  build:
    needs: prepare
    runs-on: ubuntu-latest
    steps:
      - run: |
          echo "Building v${{ needs.prepare.outputs.version }}"
          echo "SHA: ${{ needs.prepare.outputs.sha-short }}"
          docker build -t myapp:${{ needs.prepare.outputs.version }} .
```

## Expressions dans les valeurs YAML

Les expressions peuvent apparaître dans n'importe quelle valeur de workflow :

```yaml
jobs:
  build:
    name: "Build ${{ github.ref_name }}"     # Nom dynamique du job
    runs-on: ${{ inputs.runner || 'ubuntu-latest' }}   # Valeur par défaut
    env:
      APP_VERSION: ${{ format('{0}-{1}', github.ref_name, github.run_number) }}
    steps:
      - run: echo "Version : $APP_VERSION"
```

## Évaluation conditionnelle vs `if:`

La clause `if:` est évaluée **sans** `${{ }}` :

```yaml
# Correct
if: github.ref == 'refs/heads/main'

# Aussi correct (inutile mais valide)
if: ${{ github.ref == 'refs/heads/main' }}

# Courant pour les expressions complexes
if: |
  github.event_name == 'push' &&
  github.ref == 'refs/heads/main' &&
  !contains(github.event.head_commit.message, '[skip ci]')
```

## Pattern : skip CI sur demande

Une convention répandue est d'ignorer le workflow si le message de commit contient `[skip ci]` :

```yaml
jobs:
  test:
    if: "!contains(github.event.head_commit.message, '[skip ci]')"
    runs-on: ubuntu-latest
    steps:
      - run: pytest
```

> **Exercice** : Ajoutez au workflow `ci.yml` de `demo-api` un job `notify` qui :
> 1. S'exécute **toujours** (`always()`), que les tests aient réussi ou échoué.
> 2. Affiche "Tests réussis !" si les tests ont passé, ou "Tests échoués !" si ils ont échoué.
> 3. Ne s'exécute que sur des pushs vers `main` (pas sur les PRs).

<details>
<summary>Solution</summary>

```yaml
  notify:
    needs: test
    runs-on: ubuntu-latest
    if: always() && github.event_name == 'push' && github.ref == 'refs/heads/main'
    steps:
      - name: Résultat des tests
        run: |
          if [ "${{ needs.test.result }}" == "success" ]; then
            echo "Tests réussis !"
          else
            echo "Tests échoués ! Statut : ${{ needs.test.result }}"
          fi
```

Points clés :
- `always()` dans `if:` est nécessaire car sans lui, le job `notify` serait ignoré si `test` a échoué (le comportement par défaut de `needs` est de ne pas démarrer si un job dépendant a échoué).
- `needs.test.result` retourne `"success"`, `"failure"`, `"cancelled"` ou `"skipped"`.
- La combinaison `always() && github.event_name == 'push'` signifie "toujours exécuter, mais seulement si on est sur un push".

</details>
