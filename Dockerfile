version: '2'
services:
 web:
   image: vulhub/django:1.11.4
   volumes:
    - .:/app
   ports:
    - "8000:8000"
   depends_on:
    - db 
   environment:
    - DATABASE_URL=postgres://postgres:postgres@db:5432/postgres
 db:
   image: postgres:9.6-alpine
   environment:
    - POSTGRES_PASSWORD=postgres
