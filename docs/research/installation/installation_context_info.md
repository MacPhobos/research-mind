# Assumptions and ideas required for providing an easy installation process

This document describes peripheral information required to provide an easy installation process for Research Mind projects.
We already have GETTING_STARTED.md and README.md files in each or some of the projects, this document is intended to provide additional information required to make the installation process as smooth as possible.

## Research Mind project structure

Research Mind mono repo:  git@github.com:MacPhobos/research-mind.git
Research Mind service: git@github.com:MacPhobos/research-mind-service.git
Research Mind UI: git@github.com:MacPhobos/research-mind-ui.git

The monorepo git project does not contain the Research Mind UI and Service projects as git submodules. 
These need to be cloned separately into the monorepo root directory. 

## Intended Operating Systems
- Linux
- macOS
- Windows is **not** supported or tested at this time. You may try but you are on your own if you do.

## Installation methods

### Manual installation

Installing manually requires availability of certain tooling dependencies.
How that tooling is installed depends on the host operating system.
The ideal scenario is to use ASDF version manager to install the required tooling dependencies, see: https://asdf-vm.com/guide/getting-started.html
Installation and configuration of ASDF is outside the scope of this document, we will assume that it is already installed and configured before proceeding with the installation of Research Mind projects.

**CRITICAL** ASDF version 0.18.0+ is required. Never install a lesser version.  

tool versions (major/minor is sufficient, patch versions may vary):
python 3.12.11  -- required for research-mind-service
nodejs 22.21.1 -- required for research-mind-ui
uv 0.9.26 -- required for research-mind-service
pipx 1.8.0 -- required to install claude-mpm and mcp-vector-search

The .tool-versions file in each project already specifies the required tooling versions.
assuming that ASDF is installed and configured already, the installation of tooling would involve:

adding tool plugins for python, nodejs and uv:
```
asdf plugin add python
asdf plugin add nodejs
asdf plugin add uv
asdf plugin add pipx
```

followed by running `asdf install` in the root of monorepo and each project to install the required tooling versions.

#### Postgres installation or availability

You can easily use a currently installed postgres database if you have one available. 
The requirements state Postgres 18.x or later, however you might be able to use an earlier version if needed (it is up to the user to test that).
The key point is to set user/pass/port via the DATABASE_URL in .env file in research-mind-service project.

In case you do not have a postgres database available, you can easily set up a standalone postgres 18 instance using Docker.
 - the docker-compose-standalone-postgres.yml in research-mind-service/ project provides a simple configuration to run a standalone postgres instance in a docker container.
 - you can start the container using `docker compose -f docker-compose-standalone-postgres.yml up -d`
 
In either case (postgres installed locally or via docker), you need to ensure that the DATABASE_URL in .env file in research-mind-service project is set correctly to point to the correct postgres port.
This is already configured to assume port 5432 which is the default postgres port, so if you have a local postgres instance running on that port, you do not need to change it. The docker-compose-standalone-postgres.yml also uses that port. 

### Docker based installation

This is the ideal production like installation method if you want to avoid installing tooling dependencies and postgres locally.
The instructions are present in GETTING_STARTED.md but may not be accurate in light of the content of this document, we will need to review and update them as needed to ensure that they are accurate and up to date.  

The idea behind the docker based installation is to use docker compose to run the required services in a single docker container, including the research-mind-service, research-mind-ui and a postgres database.
The docker docker-compose.yml and Dockerfile.combined files are already present in the monorepo and provide the configuration to run the services in a docker container.
These files may not be accurate in light of the content of this document, we will need to review and update them as needed to ensure that they are accurate and up to date.

#### Tooling dependencies for docker based installation

Installing correcting tooling dependencies would ideally use ASDF in the docker container as well.
however this is not strictly required as we can also install the required tooling dependencies directly in the docker container without using ASDF.
The key point is to ensure that the correct versions of the tooling dependencies are installed in the docker container, as specified in the .tool-versions files in each project.
In case the versions specified in .tool-versions files change in the future the corresponding docker files would need to be updated to ensure that the correct versions are installed in the docker container.
Ideally we do want to use ASDF in this case, unless we encounter critical issues that prevent us from doing so, as this would ensure that the tooling versions are consistent between the local installation and the docker based installation.

## research-mind-service configuration

The research-mind-service project requires certain configuration to be set in the .env file in order to run correctly.
The .env file is not committed to the git repository, however a .env-example file is present in the research-mind-service project which provides an example of the required configuration.
A minimal .env file should have these options (with example values, subject to change based on docker environment and setup requirements):
```
# Server
SERVICE_ENV=development
SERVICE_HOST=0.0.0.0
SERVICE_PORT=15010

# Database
DATABASE_URL=postgresql+psycopg://mac@localhost:5432/research_mind

# CORS
CORS_ORIGINS=http://localhost:15000

# Auth (stubs - configure for production)
SECRET_KEY=dev-secret-change-in-production
ALGORITHM=HS256

# mcp-vector-search
HF_HOME=${HOME}/.cache/huggingface
TRANSFORMERS_CACHE=${HF_HOME}/transformers
HF_HUB_CACHE=${HF_HOME}/hub

# Vector Search (Phase 1.0+)
VECTOR_SEARCH_ENABLED=true
VECTOR_SEARCH_MODEL=all-MiniLM-L6-v2

# --- Logging ---
# Controls the verbosity of application logs.
# Valid levels: DEBUG, INFO, WARNING, ERROR, CRITICAL
# DEBUG: Most verbose - includes all debug messages
# INFO: Standard operational messages (default)
# WARNING: Potential issues that don't prevent operation
# ERROR: Errors that affect specific operations
# CRITICAL: Severe errors that may crash the application
LOG_LEVEL=DEBUG
```

The .env is required to run the research-mind-service project, so ensure that it is created and configured correctly before running the service.

This project is python based and provides its requirements in pyproject.toml. To install these dependencies use: 
```
uv sync --dev
```

to run the production version use: 
```
make run-prod


## research-mind-ui configuration

To ensure we have correct tooling versions installed (assuming ASDF is configured and we have added asdf plugins) run:
```
asdf install
```

To install node dependencies run:
```
npm install
```

to start the UI run:
```
make dev
```

# Question

This is a research task to provide suggestions on how to improve the installation process and documentation.
You must research what is provided in this prompt and also research what is currently available in the monorepo as well as the research-mind-service/ and research-mind-ui/ projects. 
Provide research finding in docs/research/installation/ 
You must ask questions when unclear or are able to provide better choices based on my answers. 


