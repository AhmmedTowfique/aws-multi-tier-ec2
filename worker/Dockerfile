# ============================================
# Stage 1: BUILD — uses the full SDK (~750 MB)
# ============================================
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY Worker.csproj .
RUN dotnet restore
COPY . .
RUN dotnet publish -c Release -o /app/publish --no-restore

# ============================================
# Stage 2: RUNTIME — uses just the runtime (~200 MB)
# ============================================
FROM mcr.microsoft.com/dotnet/runtime:8.0 AS runtime
WORKDIR /app
COPY --from=build /app/publish ./

RUN groupadd -r appuser && useradd -r -g appuser appuser && \
    chown -R appuser:appuser /app
USER appuser

ENV DB_HOST=db REDIS_HOST=redis
ENTRYPOINT ["dotnet", "Worker.dll"]