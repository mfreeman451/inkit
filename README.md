# Senior Software Engineer Interview Scenario: Visual Assistant API

This project simulates a multi-stage backend development interview task focused on building a RESTful API with AI integration, streaming, history, and database persistence.

## Setup and Running

### Option 1: Using pipenv (Recommended for Unix-based systems)

This project uses `pipenv` for dependency management.

1. **Prerequisites:**
   * Python 3.8+
   * `pipenv` installed (`pip install pipenv`)

2. **Install Dependencies:**
   ```bash
   pipenv install
   ```

3. **Run the Flask Application:**
   ```bash
   pipenv run python app.py
   ```
   The API will be available at `http://127.0.0.1:5000`.

### Option 2: Using venv (Alternative for Windows)

If you're on Windows and encounter issues with pipenv, you can use Python's built-in venv:

1. **Prerequisites:**
   * Python 3.8+
   * Git Bash or PowerShell (recommended for better command-line experience)

2. **Create and Activate Virtual Environment:**
   ```bash
   # Create virtual environment
   python -m venv venv

   # Activate virtual environment
   # In PowerShell:
   .\venv\Scripts\Activate.ps1
   # In Git Bash:
   source venv/Scripts/activate
   # In Command Prompt:
   .\venv\Scripts\activate.bat
   ```

3. **Install Dependencies:**
   ```bash
   pip install -r requirements.txt
   ```

4. **Run the Flask Application:**
   ```bash
   python app.py
   ```
   The API will be available at `http://127.0.0.1:5000`.

### Troubleshooting Windows Setup

If you encounter any issues with the setup on Windows:

1. **Python Path Issues:**
   - Ensure Python is added to your system's PATH
   - Try using the full path to Python: `C:\Path\To\Python\python.exe -m venv venv`

2. **Virtual Environment Activation:**
   - If activation fails, try running PowerShell as Administrator
   - For PowerShell, you might need to set the execution policy:
     ```powershell
     Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
     ```

3. **Dependency Installation:**
   - If pip install fails, try updating pip first:
     ```bash
     python -m pip install --upgrade pip
     ```
   - For SSL errors, you might need to install certificates:
     ```bash
     pip install --upgrade certifi
     ```

4. **Port Issues:**
   - If port 5000 is in use, you can change it in app.py:
     ```python
     app.run(debug=True, threaded=True, port=5001)  # or any other available port
     ```

## Interview Questions

This interview is divided into four parts, progressively building upon the API. You will start with the provided `app.py` template and modify it to meet the requirements of each question.

## Question 1: Foundational API - Image Upload and Basic Chat

**Context:**
We want to build the initial version of a "Visual Assistant". Users should be able to upload an image, receive some initial analysis, and then ask questions about that image.

**Requirements:**
1. Implement a RESTful endpoint for image upload that:
   - Accepts image files via multipart form
   - Validates file types and content
   - Handles concurrent uploads efficiently
   - Implements proper error handling
   - Returns appropriate status codes and error messages
   - Generates unique identifiers for uploaded images
   - Stores image metadata securely

2. Implement a chat endpoint that:
   - Accepts questions about uploaded images
   - Validates input and handles errors appropriately
   - Returns responses in a format compatible with the mock AI service
   - Implements proper error handling and status codes
   - Handles concurrent requests efficiently

3. Implement the mock AI service response structures:
   - Research and implement the correct response format for `mock_openai_vision_analysis`
   - Research and implement the correct response format for `mock_openai_chat` (non-streaming)
   - Ensure response formats match the OpenAI API specifications
   - Include all required fields in the response (e.g., IDs, timestamps, tokens, etc.)
   - Handle edge cases in the mock responses

## Question 2: Improving User Experience - Streaming Responses

**Context:**
The delay in the chat endpoint can be long. We want to improve this by streaming the response back to the client as it becomes available.

**Requirements:**
1. Implement a streaming endpoint that:
   - Streams responses using Server-Sent Events (SSE)
   - Handles connection drops and implements reconnection logic
   - Implements proper backpressure handling
   - Maintains compatibility with the mock AI service
   - Handles concurrent streaming connections efficiently
   - Implements proper error handling and status codes

2. Implement the streaming mock AI service:
   - Research and implement the correct SSE event format
   - Implement the streaming version of `mock_openai_chat`
   - Ensure streaming events match the OpenAI API specifications
   - Include all required event types (e.g., created, delta, completed)
   - Handle streaming edge cases and errors
   - Implement proper event sequencing and timing

## Question 3: Adding Context - History

**Context:**
Currently, each chat interaction is independent. We want the assistant to remember the conversation history for a specific image.

**Requirements:**
1. Implement conversation history that:
   - Stores chat history for each image
   - Handles concurrent access to history
   - Implements proper error handling
   - Maintains data consistency
   - Handles history for both streaming and non-streaming responses
   - Implements proper cleanup of old history

2. Update mock functions to handle history:
   - Modify mock functions to consider conversation context
   - Implement proper history integration in responses
   - Handle history-related edge cases
   - Ensure history is properly reflected in both streaming and non-streaming responses

## Question 4: Production Readiness - Persistent Storage

**Context:**
The current in-memory storage is not suitable for production. We need to implement a proper database solution.

**Requirements:**
1. Implement a database solution that:
   - Uses a production-ready database
   - Implements proper database migrations
   - Handles concurrent database access
   - Implements a caching layer
   - Maintains data consistency
   - Implements proper error handling
   - Handles database connection issues
   - Implements proper cleanup of old data

2. Update mock functions for production:
   - Ensure mock functions work with the database layer
   - Implement proper error handling for database operations
   - Handle database-related edge cases
   - Ensure mock responses remain consistent with database state

## Additional Requirements

Throughout the implementation, consider:
1. Security:
   - Implement rate limiting
   - Validate all inputs
   - Handle file uploads securely
   - Implement proper error handling
   - Protect against common security vulnerabilities

2. Performance:
   - Handle concurrent requests efficiently
   - Implement proper caching
   - Optimize database queries
   - Handle large files efficiently
   - Implement proper resource cleanup

3. Reliability:
   - Handle errors gracefully
   - Implement proper logging
   - Handle edge cases
   - Implement proper monitoring
   - Handle system failures gracefully

4. Scalability:
   - Design for horizontal scaling
   - Implement proper load balancing
   - Handle increased load gracefully
   - Implement proper resource management
   - Design for future growth # inkit
