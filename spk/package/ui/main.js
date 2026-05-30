(() => {
  "use strict";
  const VueRef = Vue;

  const App = VueRef.extend({
    name: "App",
    data() {
      return {
        activeTab: "status",
        responseText: "",
        loading: false,
        error: null,
        showClearButton: false,
      };
    },
    mounted() {
      this.fetchData();
      this.$nextTick(() => {
        const el = this.$refs.contentArea;
        if (el) {
          el.focus?.();
          el.addEventListener("scroll", this.handleScroll);
        }
      });
    },
    beforeDestroy() {
      const el = this.$refs.contentArea;
      if (el) {
        el.removeEventListener("scroll", this.handleScroll);
      }
    },
    methods: {
      setTab(tab) {
        this.activeTab = tab;
        this.fetchData();
      },
      async fetchData() {
        this.loading = true;
        this.error = null;
        this.responseText = "";
        this.showClearButton = false;

        const basePath = "/webman/3rdparty/YandexDisk/scripts/";
        const endpoint = `${basePath}${this.activeTab}.cgi`;

        try {
          const res = await fetch(endpoint, {
            credentials: "same-origin",
          });
          if (!res.ok) throw new Error("Ошибка загрузки скрипта");

          const text = await res.text();
          this.responseText = text;
        } catch (err) {
          this.error = err.message;
        } finally {
          this.loading = false;
          this.$nextTick(() => {
            const el = this.$refs.contentArea;
            if (el) el.focus?.();
          });
        }
      },
      handleScroll() {
        const el = this.$refs.contentArea;
        if (!el) return;

        const threshold = 40;
        const scrolledToBottom =
          el.scrollHeight - el.scrollTop - el.clientHeight < threshold;

        this.showClearButton = scrolledToBottom && this.activeTab === "log";
      },
      async confirmClearLogs() {
        if (!confirm("Вы действительно хотите очистить логи?")) return;

        try {
          await fetch("/webman/3rdparty/YandexDisk/scripts/clear_log.cgi", {
            method: "POST",
            credentials: "same-origin",
          });
          this.fetchData();
        } catch (err) {
          alert("Ошибка очистки: " + err.message);
        }
      },
    },
    template: `
      <v-app-instance class-name="SYNOCOMMUNITY.YandexDisk.AppInstance">
        <v-app-window
          ref="appWindow"
          syno-id="SYNOCOMMUNITY.YandexDisk.Window"
          :width="800"
          :height="500"
          :resizable="true"
        >
          <div class="yandex-disk-app">
            <!-- Верхние кнопки -->
            <div class="top-buttons">
              <v-button
                suffix="main"
                :class="{ active: activeTab === 'status' }"
                @click="setTab('status')"
              >
                Статус
              </v-button>
              <v-button
                suffix="main"
                :class="{ active: activeTab === 'log' }"
                @click="setTab('log')"
              >
                Лог
              </v-button>
              <v-button
                suffix="main"
                :class="{ active: activeTab === 'sync_log' }"
                @click="setTab('sync_log')"
              >
                Синхронизация
              </v-button>
            </div>

            <!-- Контент -->
            <div
              class="content-area"
              tabindex="0"
              ref="contentArea"
            >
              <div v-if="loading">Загрузка...</div>
              <div v-else-if="error" style="color: red">Ошибка: {{ error }}</div>
              <pre v-else class="result">{{ responseText }}</pre>

              <!-- Кнопка очистки логов -->
				<v-button
					v-if="showClearButton"
					class="v-button--red clear-logs-btn"
					suffix="red"
					@click="confirmClearLogs"
				>
					Очистить
				</v-button>
            </div>
          </div>
        </v-app-window>
      </v-app-instance>
    `,
  });

  SYNO.namespace("SYNOCOMMUNITY.YandexDisk");
  SYNOCOMMUNITY.YandexDisk.AppInstance = VueRef.extend({
    components: { App },
    template: "<App/>",
  });
})();