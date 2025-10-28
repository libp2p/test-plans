FROM python:3.12-slim
ENTRYPOINT ["/bin/sh", "-c", "iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE && exec python hole_punch_test.py"]
WORKDIR /app
COPY pyproject.toml .
RUN pip install --no-cache-dir -e .
COPY hole_punch_test.py .
VOLUME /results
CMD ["python", "hole_punch_test.py"]