using System;

namespace MRSDistCompWebApp.Models
{
    public class DataSource
    {
        public Guid Id { get; set; }
        public string Name { get; set; }       
        public string Description { get; set; }
        public string Type { get; set; } = "csv";
        public string ModelSchema { get; set; }
        public string AccessInfo { get; set; }
        public bool IsEnabled { get; set; }
    }
}
