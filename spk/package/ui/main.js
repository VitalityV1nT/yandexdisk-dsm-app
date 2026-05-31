(() => {
  "use strict";
  const VueRef = Vue;

  // Tab key -> CGI endpoint name (status.cgi / log.cgi / sync_log.cgi). The KEYS are
  // part of the URL and must not change; only the human labels below were renamed for
  // clarity ("Лог" -> "История", "Синхронизация" -> "Журнал синхронизации").
  const TABS = [
    { key: "status", label: "Статус" },
    { key: "log", label: "История" },
    { key: "sync_log", label: "Журнал синхронизации" },
  ];

  // One-line caption shown under the tab bar so the two log-like tabs aren't confused.
  const CAPTIONS = {
    status: "Текущее состояние, папка и время последней синхронизации",
    log: "Краткая история состояний синхронизации",
    sync_log: "Подробный технический лог последней синхронизации (rclone)",
  };

  const App = VueRef.extend({
    name: "App",
    data() {
      return {
        activeTab: "status",
        responseText: "",
        loading: false,
        error: null,
        tabs: TABS,
      };
    },
    computed: {
      tabCaption() {
        return CAPTIONS[this.activeTab] || "";
      },
    },
    mounted() {
      this.fetchData();
      this.$nextTick(() => {
        this.$refs.contentArea?.focus?.();
      });
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
      async confirmClearLogs() {
        if (!confirm("Вы действительно хотите очистить историю синхронизации?")) return;

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
            <!-- Вкладки -->
            <div class="top-buttons">
              <v-button
                v-for="tab in tabs"
                :key="tab.key"
                suffix="main"
                :class="{ active: activeTab === tab.key }"
                @click="setTab(tab.key)"
              >
                {{ tab.label }}
              </v-button>
              <!-- Кнопка очистки истории — постоянно видна на вкладке «История» -->
              <v-button
                v-if="activeTab === 'log'"
                class="v-button--red clear-logs-btn"
                suffix="red"
                @click="confirmClearLogs"
              >
                Очистить
              </v-button>
            </div>

            <!-- Подпись активной вкладки -->
            <div class="tab-caption">{{ tabCaption }}</div>

            <!-- Контент -->
            <div
              class="content-area"
              tabindex="0"
              ref="contentArea"
            >
              <div v-if="loading">Загрузка...</div>
              <div v-else-if="error" style="color: red">Ошибка: {{ error }}</div>
              <pre v-else class="result">{{ responseText }}</pre>
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
