# FIX-CONNEXXA

## Installation

To install the application, run the following command:

```bash
npm install
```

## API Endpoints

### List Users

```bash
curl -X GET http://your-api-url.com/api/users
```

### Create User

```bash
curl -X POST http://your-api-url.com/api/users -H "Content-Type: application/json" -d '{"name": "John Doe", "email": "john@example.com"}'
```

### Update User

```bash
curl -X PUT http://your-api-url.com/api/users/{id} -H "Content-Type: application/json" -d '{"name": "Jane Doe"}'
```

### Delete User

```bash
curl -X DELETE http://your-api-url.com/api/users/{id}
```

## System Requirements

- Node.js version >= 12.x
- npm version >= 6.x
- MongoDB version >= 4.x

## Troubleshooting Guide

- **Error: ENOENT** - This error indicates that a file or directory was not found. Ensure all required files are in place.

- **Error: EACCES** - This error indicates that permission is denied. Make sure you have the necessary permissions to access the files.

## File Structure Overview

```
/FIX-CONNEXXA
|-- /src
|   |-- /controllers
|   |-- /models
|   |-- /routes
|   |-- /middlewares
|-- /tests
|-- package.json
|-- server.js
```

## Testing Commands

To run the tests, use the following command:

```bash
npm test
```

## Swagger UI

You can access the Swagger UI documentation at:

```
http://your-api-url.com/api-docs
```
