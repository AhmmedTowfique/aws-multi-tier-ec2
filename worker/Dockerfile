# ============================================
# Stage 1: Build — uses the full .NET SDK
# ============================================
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

# Copy only the project file first and restore — this layer gets cached
# so subsequent code-only changes don't reinstall NuGet packages
COPY Worker.csproj .
RUN dotnet restore

# Copy the rest of the source and publish a trimmed release build
COPY . .
RUN dotnet publish -c Release -o /app/publish --no-restore

# ============================================
# Stage 2: Runtime — uses the slim .NET runtime
# ============================================
FROM mcr.microsoft.com/dotnet/runtime:8.0 AS runtime
WORKDIR /app

# Copy only the compiled output from the build stage
COPY --from=build /app/publish ./

# Only bake in internal conventions — service names on the Docker network.
# Credentials and DB name come from docker-compose → .env at runtime.
ENV DB_HOST=db \
    REDIS_HOST=redis

# Worker has no EXPOSE and no ports in compose — it's outbound-only.
ENTRYPOINT ["dotnet", "Worker.dll"]