FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY sub2api-admin-mcp.py .

EXPOSE 8765

CMD ["python", "sub2api-admin-mcp.py"]
