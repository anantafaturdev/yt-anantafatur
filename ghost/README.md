# Ghost Blog with MySQL (Docker Compose)

This repository contains a Docker Compose setup for running a Ghost blog with a MySQL database. It also includes SMTP configuration for sending emails (e.g., sign-up notifications, password resets).

---

## Features

- Ghost 6.10.3 on Alpine Linux
- MySQL 8.0 as database
- Persistent storage for both Ghost content and MySQL data
- SMTP integration for email notifications
- Easy to deploy locally or on a server

---

## Prerequisites

- Docker
- Docker Compose
- (Optional) Domain with HTTPS if deploying publicly

---

## Quick Start

1. Clone the repository:

```bash
git clone https://github.com/yourusername/ghost-docker.git
cd ghost-docker
````

2. Update `.env` file (optional) or directly edit `docker-compose.yml`:

* Replace SMTP credentials and `mail_from` with your own.
* Update the `url` variable to match your domain.

3. Start the containers:

```bash
docker-compose up -d
```

4. Access your blog at [http://localhost:8087](http://localhost:8087) (or your configured domain if deployed remotely).

---

## Docker Compose Structure

```yaml
services:
  ghost:
    image: ghost:6.10.3-alpine3.23
    restart: always
    ports:
      - 8087:2368
    environment:
      database__client: mysql
      database__connection__host: db
      database__connection__user: root
      database__connection__password: YOUR_DB_PASSWORD
      database__connection__database: ghost
      url: https://yourdomain.com
      mail__transport: SMTP
      mail__options__host: mail.smtp2go.com
      mail__options__port: 587
      mail__options__auth__user: YOUR_SMTP_USER
      mail__options__auth__pass: YOUR_SMTP_PASS
      mail__from: Your Name <your@email.com>
    volumes:
      - ghost:/var/lib/ghost/content

  db:
    image: mysql:8.0-bookworm
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: YOUR_DB_PASSWORD
    volumes:
      - db:/var/lib/mysql

volumes:
  ghost:
  db:
```

---

## Notes

* Data persistence is handled with Docker volumes (`ghost` and `db`), so your content and database survive container restarts.
* Make sure to change passwords and SMTP credentials before pushing to public repositories.
* You can configure your Ghost blog further using environment variables or the admin panel.

---

## Planned Content

I’ve prepared SMTP setup and email testing scripts. The full content is planned to be published next week.
