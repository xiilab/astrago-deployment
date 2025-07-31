# Use Bitnami Keycloak image as base
FROM bitnami/keycloak:22.0.5

# Set environment variables
ENV KC_HEALTH_ENABLED=true
ENV KC_METRICS_ENABLED=true
ENV KC_FEATURES=preview

# Switch to root to copy files
USER root

# Install wget if not available
RUN apt-get update && apt-get install -y wget && rm -rf /var/lib/apt/lists/*

# Copy the built JAR to Keycloak providers directory
COPY target/keycloak-astrago-spi-1.0.0.jar /opt/bitnami/keycloak/providers/

# Download theme JAR to the same providers directory
RUN wget -O /opt/bitnami/keycloak/providers/keycloak-theme.jar \
    https://github.com/xiilab/uyuni-login-theme/releases/download/v1.1.16/keycloak-theme.jar

# Set proper permissions for all files in providers directory
RUN chown -R 1001:1001 /opt/bitnami/keycloak/providers/

# Switch back to keycloak user
USER 1001

# Expose Keycloak port
EXPOSE 8080

# Set the default command
ENTRYPOINT ["/opt/bitnami/scripts/keycloak/entrypoint.sh"]
CMD ["/opt/bitnami/scripts/keycloak/run.sh"] 