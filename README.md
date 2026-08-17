# DevOps To-Do App — Dockerized · AWS EC2 · GitHub Actions CI/CD

A deliberately simple Flask to-do list app used as a vehicle to demonstrate a real,
end-to-end DevOps workflow: containerize an app, ship it to the cloud, and automate
deployment so every `git push` goes live without manual steps.

## Architecture

```
Developer                GitHub                  Docker Hub              AWS EC2
    |                       |                          |                     |
    | git push main         |                          |                     |
    |---------------------->|                          |                     |
    |                       | GitHub Actions triggers  |                     |
    |                       |------------------------->|                     |
    |                       | 1. docker build           |                    |
    |                       | 2. docker push image ---->| stores image       |
    |                       |                          |                     |
    |                       | 3. SSH into EC2 ---------------------------->  |
    |                       |    docker pull latest                          |
    |                       |    docker stop/rm old container                |
    |                       |    docker run new container on port 80         |
    |                       |                                                |
    |  <---------------------------------------- App live at http://EC2_IP ->|
```

**Flow in plain English:** you push code → GitHub Actions builds a Docker image →
pushes it to Docker Hub → SSHes into your EC2 server → pulls the new image →
replaces the running container. Zero manual deployment steps after setup.

## Tech Stack

| Layer            | Choice                        | Why |
|-------------------|-------------------------------|-----|
| App               | Python 3.12 + Flask           | Small, easy to read, fast to containerize |
| WSGI server       | Gunicorn                      | Flask's dev server isn't safe for production |
| Data              | SQLite (file, via Docker volume) | Zero setup, persists across container restarts |
| Containerization  | Docker                        | Portable, identical environment everywhere |
| CI/CD             | GitHub Actions                | Free, integrated with GitHub, industry-standard |
| Image registry    | Docker Hub                    | Free public registry, simplest option to start |
| Compute           | AWS EC2 (Ubuntu, t2.micro — free tier) | Simplest way to run a container on a real server |

> **Note on EC2 vs ECS:** This project deploys to a single EC2 instance running
> Docker directly — the simplest possible "real" cloud deployment, and the best
> starting point for learning. Once this works, the natural next step is migrating
> to **ECS Fargate** (fully managed containers, no server to patch, auto-scaling).
> That's a good "phase 2" to mention in an interview as your next planned step.

## Project Structure

```
todo-app/
├── app.py                      # Flask application
├── templates/index.html        # UI
├── static/style.css            # Styling
├── requirements.txt            # Python dependencies
├── Dockerfile                  # Container build instructions
├── docker-compose.yml          # Local dev convenience
├── .dockerignore
├── .gitignore
└── .github/workflows/deploy.yml # CI/CD pipeline
```

---

## Part 1 — Run it locally (no Docker)

```bash
pip install -r requirements.txt
python app.py
# open http://localhost:5000
```

## Part 2 — Run it in Docker locally

```bash
docker build -t todo-app .
docker run -d -p 5000:5000 -v todo-data:/app/data --name todo-app todo-app
# open http://localhost:5000

# or, using docker-compose:
docker compose up --build
```

Check the image was built and container is healthy:
```bash
docker ps
docker logs todo-app
```

## Part 3 — Push the image to Docker Hub (manual, once, to confirm it works)

```bash
docker login
docker tag todo-app YOUR_DOCKERHUB_USERNAME/todo-app:latest
docker push YOUR_DOCKERHUB_USERNAME/todo-app:latest
```

## Part 4 — Launch the AWS EC2 instance

1. AWS Console → **EC2** → **Launch Instance**.
2. Name: `todo-app-server`.
3. AMI: **Ubuntu Server 22.04 LTS** (free tier eligible).
4. Instance type: **t2.micro** (free tier).
5. Key pair: create a new one, e.g. `todo-app-key`, download the `.pem` file
   and keep it safe — you cannot re-download it.
6. Network settings → Edit security group → allow:
   - SSH (port 22) from **My IP** (not 0.0.0.0/0 — keep SSH restricted to you)
   - HTTP (port 80) from **Anywhere**
7. Launch the instance. Note its **Public IPv4 address**.

SSH in and install Docker (one-time setup on the server):

```bash
ssh -i todo-app-key.pem ubuntu@YOUR_EC2_PUBLIC_IP

# on the EC2 instance:
sudo apt update
sudo apt install -y docker.io
sudo systemctl enable --now docker
sudo usermod -aG docker ubuntu
# log out and back in for group change to apply
```

Do one manual deploy to confirm everything works end-to-end before automating:

```bash
docker pull YOUR_DOCKERHUB_USERNAME/todo-app:latest
docker run -d --name todo-app -p 80:5000 -v todo-data:/app/data --restart unless-stopped YOUR_DOCKERHUB_USERNAME/todo-app:latest
```

Visit `http://YOUR_EC2_PUBLIC_IP` in a browser — you should see the to-do app live.

## Part 5 — Wire up GitHub Actions (the automation)

1. Push this project to a new GitHub repo.
2. In Docker Hub: **Account Settings → Security → New Access Token** (don't use your password).
3. In your GitHub repo: **Settings → Secrets and variables → Actions → New repository secret**,
   add each of these:

   | Secret name | Value |
   |---|---|
   | `DOCKERHUB_USERNAME` | your Docker Hub username |
   | `DOCKERHUB_TOKEN` | the access token from step 2 |
   | `EC2_HOST` | your EC2 public IP |
   | `EC2_USER` | `ubuntu` |
   | `EC2_SSH_KEY` | the **full contents** of your `.pem` file |

4. Push a commit to `main`. Go to the **Actions** tab in GitHub and watch the
   pipeline run: build → push → deploy.
5. Refresh `http://YOUR_EC2_PUBLIC_IP` — your change is live, with no manual
   deploy step.

That's the whole loop: **code → push → build → ship → running in the cloud**, automatically.

## Troubleshooting

- **Actions job fails at SSH step:** double check `EC2_SSH_KEY` includes the
  `-----BEGIN ... KEY-----` / `-----END ... KEY-----` lines exactly as in the `.pem` file.
- **Can't reach the app in a browser:** check the EC2 security group allows
  inbound port 80, and that `docker ps` on the instance shows the container running.
- **Container keeps restarting:** `docker logs todo-app` on the EC2 box to see the error.

## Possible Next Steps (good talking points for interviews)

- Move from a single EC2 box to **ECS Fargate** for managed scaling and no OS patching.
- Put the EC2 instance behind an **Application Load Balancer** + auto-scaling group.
- Replace SQLite with **RDS (PostgreSQL)** for a real managed database.
- Add **Terraform** to define the EC2 instance and security group as code instead
  of clicking through the console.
- Add a `test` job to the GitHub Actions pipeline that runs before build/deploy.
- Push the image to **Amazon ECR** instead of Docker Hub, and use IAM roles
  instead of long-lived SSH keys for a more "production" security posture.
