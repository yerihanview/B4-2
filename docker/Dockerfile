
FROM ubuntu:22.04

# 애플리케이션 실행용 일반 사용자
RUN useradd --create-home --shell /bin/bash agent

# 기본 경로
ENV AGENT_HOME=/home/agent/agent-app
ENV AGENT_LOG_DIR=/home/agent/agent-app/logs

# 필요한 디렉터리 생성
RUN mkdir -p \
    $AGENT_HOME/upload_files \
    $AGENT_HOME/api_keys \
    $AGENT_LOG_DIR \
    && chown -R agent:agent /home/agent

# Linux x86-64 실행 파일 복사
COPY --chown=agent:agent app/agent-leak-app-x86 /home/agent/agent-app/agent-leak-app

# 실행 권한 부여
RUN chmod 750 /home/agent/agent-app/agent-leak-app

# 일반 사용자로 실행
USER agent
WORKDIR /home/agent/agent-app

# 애플리케이션 포트
EXPOSE 15034

CMD ["./agent-leak-app"]
